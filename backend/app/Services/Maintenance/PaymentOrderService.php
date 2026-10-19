<?php

namespace App\Services\Maintenance;

use App\Models\MaintenanceBill;
use App\Models\MaintenancePayment;
use App\Models\PaymentOrder;
use App\Models\PaymentOrderItem;
use App\Models\PaymentReceipt;
use App\Models\Penalty;
use App\Models\PenaltyAuditLog;
use App\Models\Resident;
use App\Notifications\SocietyAlert;
use App\Services\Payment\RazorpayGatewayService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class PaymentOrderService
{
    public function __construct(
        private readonly RazorpayGatewayService $razorpay = new RazorpayGatewayService(),
    ) {}

    /**
     * Generates a deterministic demo reference for a given order so repeated
     * calls to confirmDemo produce the same reference and are idempotent via
     * the unique constraint on gateway_payment_id.
     */
    private static function demoRef(PaymentOrder $order): string
    {
        return sprintf('DEMO-%s-%06d', now()->format('Ymd'), $order->id);
    }

    /**
     * Returns the client-facing due summary. Every amount is calculated
     * from bills and completed payments on the server.
     */
    public function summary(Resident $resident, ?array $billIds = null): array
    {
        $currentMonth = now()->startOfMonth();
        $items = MaintenanceBill::query()
            ->withSum([
                'payments as paid_amount' => fn ($query) => $query
                    ->where('status', MaintenancePayment::STATUS_COMPLETED),
            ], 'amount')
            ->where('flat_id', $resident->flat_id)
            ->whereNotIn('status', [MaintenanceBill::STATUS_CANCELLED])
            ->when($billIds !== null, fn ($query) => $query->whereIn('id', $billIds))
            ->orderBy('billing_month')
            ->get()
            ->map(function (MaintenanceBill $bill): array {
                $outstanding = max(0, (float) $bill->amount - (float) ($bill->paid_amount ?? 0));

                return [
                    'bill' => $bill,
                    'outstanding' => $outstanding,
                    'factor' => (float) $bill->amount > 0 ? $outstanding / (float) $bill->amount : 0,
                ];
            })
            ->filter(fn (array $item) => $item['outstanding'] > 0)
            ->values();

        $currentItems = $items->filter(fn (array $item) => $item['bill']->billing_month->gte($currentMonth));
        $maintenance = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'base_maintenance'));
        $water = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'water_charge'));
        $electricity = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'electricity_common_area_charge'));
        $parking = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'parking_charge'));
        $other = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'other_charges'));
        $lateFee = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'late_fee'));
        $discount = $currentItems->sum(fn (array $item) => $this->componentAmount($item, 'discount'));

        // Bills created before component support have only `amount`. They are
        // correctly shown as maintenance instead of inventing a charge split.
        $legacyMaintenance = $currentItems
            ->filter(fn (array $item) => ! $this->hasChargeComponents($item['bill']))
            ->sum('outstanding');
        $previousDues = $items
            ->filter(fn (array $item) => $item['bill']->billing_month->lt($currentMonth))
            ->sum('outstanding');

        return [
            'currency' => 'INR',
            'as_of' => now()->toISOString(),
            'maintenance' => round($maintenance + $legacyMaintenance, 2),
            'water_charge' => round($water, 2),
            'electricity_common_area_charge' => round($electricity, 2),
            'parking_charge' => round($parking, 2),
            'other_charges' => round($other, 2),
            'late_fee' => round($lateFee, 2),
            'discount' => round($discount, 2),
            'previous_dues' => round($previousDues, 2),
            'total_due' => round($items->sum('outstanding'), 2),
            'bill_count' => $items->count(),
        ];
    }

    /**
     * Creates one server-calculated order for outstanding bills of the
     * authenticated resident. In demo mode (PAYMENT_MODE=demo), it immediately
     * confirms the order, marks all included bills paid, and generates a receipt.
     */
    public function initiateFullPayment(Resident $resident, string $method, ?array $billIds = null): PaymentOrder
    {
        return DB::transaction(function () use ($resident, $method, $billIds): PaymentOrder {
            $isDemo = config('app.payment_mode', 'live') === 'demo';

            if ($billIds !== null) {
                $ownedCount = MaintenanceBill::query()
                    ->where('flat_id', $resident->flat_id)
                    ->whereIn('id', $billIds)
                    ->count();

                if ($ownedCount !== count($billIds)) {
                    throw ValidationException::withMessages([
                        'maintenance_bill_ids' => 'One or more selected invoices do not belong to your flat.',
                    ]);
                }
            }

            if (! $isDemo) {
                $existing = PaymentOrder::query()
                    ->where('resident_id', $resident->id)
                    ->whereIn('status', [PaymentOrder::STATUS_PENDING, PaymentOrder::STATUS_PROCESSING])
                    ->latest()
                    ->first();

                if ($existing) {
                    return $existing->load('items.bill');
                }
            }

            $bills = MaintenanceBill::query()
                ->where('flat_id', $resident->flat_id)
                ->whereNotIn('status', [MaintenanceBill::STATUS_CANCELLED])
                ->when($billIds !== null, fn ($query) => $query->whereIn('id', $billIds))
                ->lockForUpdate()
                ->get();

            if ($billIds !== null && $bills->count() !== count($billIds)) {
                throw ValidationException::withMessages([
                    'maintenance_bill_ids' => 'One or more selected invoices do not belong to your flat.',
                ]);
            }

            $items = $bills->map(function (MaintenanceBill $bill): array {
                $paid = (float) $bill->payments()
                    ->where('status', MaintenancePayment::STATUS_COMPLETED)
                    ->sum('amount');

                return [
                    'bill' => $bill,
                    'amount' => max(0, (float) $bill->amount - $paid),
                ];
            })->filter(fn (array $item) => $item['amount'] > 0)->values();

            if ($items->isEmpty()) {
                throw ValidationException::withMessages([
                    'payment' => 'There are no outstanding dues to pay.',
                ]);
            }

            $order = PaymentOrder::create([
                'resident_id' => $resident->id,
                'flat_id' => $resident->flat_id,
                'amount' => $items->sum('amount'),
                'payment_method' => $method,
                'status' => PaymentOrder::STATUS_PENDING,
                'provider' => $isDemo ? 'DEMO' : 'UNCONFIGURED',
                'provider_reference' => 'ORDER-'.Str::upper(Str::random(12)),
            ]);

            foreach ($items as $item) {
                PaymentOrderItem::create([
                    'payment_order_id' => $order->id,
                    'maintenance_bill_id' => $item['bill']->id,
                    'amount' => $item['amount'],
                ]);
            }

            if ($isDemo) {
                $demoRef = self::demoRef($order);
                $this->recordVerifiedOrderPayments($order, $demoRef);

                $order->update([
                    'status' => PaymentOrder::STATUS_SUCCESSFUL,
                    'gateway_payment_id' => $demoRef,
                    'verification_note' => 'Confirmed via internal demo payment (PAYMENT_MODE=demo).',
                    'verified_at' => now(),
                ]);

                PaymentReceipt::firstOrCreate(
                    ['payment_order_id' => $order->id],
                    [
                        'receipt_number' => sprintf('REC-%s-%06d', now()->format('Ymd'), $order->id),
                        'amount' => $order->amount,
                        'currency' => 'INR',
                        'payment_method' => $order->payment_method,
                        'payment_reference' => $demoRef,
                        'issued_at' => now(),
                    ],
                );

                $order->loadMissing('resident.user');
                $order->resident?->user?->notify(new SocietyAlert(
                    'payment_successful',
                    'Payment successful',
                    'Your maintenance payment has been confirmed (demo mode).',
                    ['payment_order_id' => $order->id, 'amount' => (float) $order->amount],
                ));

                return $order->fresh([
                    'resident.user', 'flat', 'items.bill', 'maintenancePayments.bill', 'receipt',
                ]);
            }

            return $order->fresh('items.bill');
        });
    }

    /**
     * Confirms a payment order internally for demo/development environments
     * (PAYMENT_MODE=demo). No external gateway is contacted. The method is
     * idempotent: if the order is already SUCCESSFUL it returns it unchanged
     * so the resident cannot be double-charged.
     *
     * All downstream effects (MaintenancePayment records, bill status,
     * PaymentReceipt, and the success notification) go through the same
     * recordVerifiedOrderPayments() path used by the admin transition, so the
     * database remains fully consistent.
     *
     * @throws ValidationException
     */
    public function confirmDemo(PaymentOrder $paymentOrder, int $residentId): PaymentOrder
    {
        return DB::transaction(function () use ($paymentOrder, $residentId): PaymentOrder {
            $order = PaymentOrder::query()
                ->with('items')
                ->lockForUpdate()
                ->findOrFail($paymentOrder->id);

            // Safety: only the owning resident may confirm their own order.
            if ((int) $order->resident_id !== $residentId) {
                throw ValidationException::withMessages([
                    'payment' => 'You do not have permission to confirm this payment order.',
                ]);
            }

            // Idempotency: already successful — return as-is, no duplicate work.
            if ($order->status === PaymentOrder::STATUS_SUCCESSFUL) {
                return $order->fresh([
                    'resident.user', 'flat', 'items.bill', 'maintenancePayments.bill', 'receipt',
                ]);
            }

            if (! in_array($order->status, [PaymentOrder::STATUS_PENDING, PaymentOrder::STATUS_PROCESSING], true)) {
                throw ValidationException::withMessages([
                    'payment' => 'Only a pending or processing order can be confirmed.',
                ]);
            }

            $demoRef = self::demoRef($order);

            // Record individual maintenance payments and update bill statuses.
            $this->recordVerifiedOrderPayments($order, $demoRef);

            $order->update([
                'status' => PaymentOrder::STATUS_SUCCESSFUL,
                'gateway_payment_id' => $demoRef,
                'verification_note' => 'Confirmed via internal demo payment (PAYMENT_MODE=demo).',
                'verified_at' => now(),
            ]);

            PaymentReceipt::firstOrCreate(
                ['payment_order_id' => $order->id],
                [
                    'receipt_number' => sprintf('REC-%s-%06d', now()->format('Ymd'), $order->id),
                    'amount' => $order->amount,
                    'currency' => 'INR',
                    'payment_method' => $order->payment_method,
                    'payment_reference' => $demoRef,
                    'issued_at' => now(),
                ],
            );

            $order->loadMissing('resident.user');
            $order->resident?->user?->notify(new SocietyAlert(
                'payment_successful',
                'Payment successful',
                'Your maintenance payment has been confirmed (demo mode).',
                ['payment_order_id' => $order->id, 'amount' => (float) $order->amount],
            ));

            return $order->fresh([
                'resident.user', 'flat', 'items.bill', 'maintenancePayments.bill', 'receipt',
            ]);
        });
    }

    /**
     * Reconciles an aggregate order only after an administrator verifies it.
     * A payment provider is deliberately not implied by this transition.
     */
    public function transition(PaymentOrder $paymentOrder, array $data): PaymentOrder
    {
        return DB::transaction(function () use ($paymentOrder, $data): PaymentOrder {
            $order = PaymentOrder::query()
                ->with('items')
                ->lockForUpdate()
                ->findOrFail($paymentOrder->id);
            $status = $data['status'];
            $allowed = match ($order->status) {
                PaymentOrder::STATUS_PENDING => [
                    PaymentOrder::STATUS_PROCESSING,
                    PaymentOrder::STATUS_SUCCESSFUL,
                    PaymentOrder::STATUS_FAILED,
                    PaymentOrder::STATUS_CANCELLED,
                ],
                PaymentOrder::STATUS_PROCESSING => [
                    PaymentOrder::STATUS_SUCCESSFUL,
                    PaymentOrder::STATUS_FAILED,
                    PaymentOrder::STATUS_CANCELLED,
                ],
                default => [],
            };

            if (! in_array($status, $allowed, true)) {
                throw ValidationException::withMessages([
                    'status' => 'Invalid payment-order status transition.',
                ]);
            }

            if ($status === PaymentOrder::STATUS_SUCCESSFUL) {
                $this->recordVerifiedOrderPayments($order, $data['gateway_payment_id']);
            }

            $order->update([
                'status' => $status,
                'gateway_payment_id' => $data['gateway_payment_id'] ?? $order->gateway_payment_id,
                'verification_note' => $data['verification_note'] ?? $order->verification_note,
                'verified_at' => $status === PaymentOrder::STATUS_SUCCESSFUL ? now() : $order->verified_at,
            ]);

            if ($status === PaymentOrder::STATUS_SUCCESSFUL) {
                PaymentReceipt::firstOrCreate(
                    ['payment_order_id' => $order->id],
                    [
                        'receipt_number' => sprintf('REC-%s-%06d', now()->format('Ymd'), $order->id),
                        'amount' => $order->amount,
                        'currency' => 'INR',
                        'payment_method' => $order->payment_method,
                        'payment_reference' => $data['gateway_payment_id'],
                        'issued_at' => now(),
                    ],
                );

                $order->loadMissing('resident.user');
                $order->resident?->user?->notify(new SocietyAlert(
                    'payment_successful',
                    'Payment successful',
                    'Your maintenance payment has been verified successfully.',
                    ['payment_order_id' => $order->id, 'amount' => (float) $order->amount],
                ));
            }

            return $order->fresh([
                'resident.user', 'flat', 'items.bill', 'maintenancePayments.bill', 'receipt',
            ]);
        });
    }

    public function cancelByResident(PaymentOrder $paymentOrder): PaymentOrder
    {
        return DB::transaction(function () use ($paymentOrder): PaymentOrder {
            $order = PaymentOrder::query()->lockForUpdate()->findOrFail($paymentOrder->id);

            if ($order->status !== PaymentOrder::STATUS_PENDING) {
                throw ValidationException::withMessages([
                    'status' => 'Only a pending payment order can be cancelled.',
                ]);
            }

            $order->update(['status' => PaymentOrder::STATUS_CANCELLED]);

            return $order->fresh('items.bill');
        });
    }

    private function recordVerifiedOrderPayments(PaymentOrder $order, string $gatewayPaymentId): void
    {
        foreach ($order->items as $item) {
            if ($item->penalty_id !== null) {
                $penalty = Penalty::query()->lockForUpdate()->findOrFail($item->penalty_id);
                if ((int) $penalty->resident_id !== (int) $order->resident_id
                    || $penalty->status !== 'approved'
                    || $penalty->payment_status !== 'unpaid'
                    || round((float) $item->amount, 2) !== round((float) $penalty->disciplinary_amount + (float) $penalty->repair_cost + (float) $penalty->late_fee_amount, 2)) {
                    throw ValidationException::withMessages(['payment' => 'This penalty is no longer eligible for this payment order.']);
                }
                $penalty->update(['payment_status' => 'paid']);
                PenaltyAuditLog::create([
                    'violation_report_id' => $penalty->violation_report_id,
                    'user_id' => $order->resident?->user_id ?? $penalty->decided_by_user_id,
                    'action' => 'payment_verified',
                    'from_status' => 'unpaid',
                    'to_status' => 'paid',
                    'reason' => 'Verified payment '.$gatewayPaymentId,
                    'details' => ['payment_order_id' => $order->id, 'amount' => (float) $item->amount],
                ]);
                $order->resident?->user?->notify(new SocietyAlert(
                    'penalty_payment_successful',
                    'Penalty payment successful',
                    'Your approved penalty payment has been verified.',
                    ['penalty_id' => $penalty->id, 'report_id' => $penalty->violation_report_id, 'payment_order_id' => $order->id, 'audience' => 'RESIDENT'],
                ));
                continue;
            }
            $bill = MaintenanceBill::query()->lockForUpdate()->findOrFail($item->maintenance_bill_id);
            $paid = (float) $bill->payments()
                ->where('status', MaintenancePayment::STATUS_COMPLETED)
                ->sum('amount');
            $outstanding = max(0, (float) $bill->amount - $paid);

            if (round($outstanding, 2) !== round((float) $item->amount, 2)) {
                throw ValidationException::withMessages([
                    'status' => 'This order can no longer be confirmed because one or more billed amounts changed. Cancel it and create a new order.',
                ]);
            }

            MaintenancePayment::query()
                ->where('maintenance_bill_id', $bill->id)
                ->where('resident_id', $order->resident_id)
                ->where('status', MaintenancePayment::STATUS_PENDING)
                ->update(['status' => MaintenancePayment::STATUS_FAILED]);

            MaintenancePayment::create([
                'payment_order_id' => $order->id,
                'maintenance_bill_id' => $bill->id,
                'resident_id' => $order->resident_id,
                'amount' => $item->amount,
                'reference_id' => sprintf('%s-BILL-%d', $order->provider_reference, $bill->id),
                'payment_method' => $order->payment_method,
                'status' => MaintenancePayment::STATUS_COMPLETED,
                'paid_at' => now(),
                'receipt_reference' => $gatewayPaymentId,
            ]);

            $this->refreshBillStatus($bill);
        }
    }

    /** Build a checkout order for one approved penalty using the verified Razorpay callback path. */
    public function createRazorpayOrderForPenalty(Resident $resident, Penalty $penalty, string $method = MaintenancePayment::METHOD_UPI): array
    {
        if (! $this->razorpay->isConfigured()) {
            throw new \App\Exceptions\PaymentGatewayUnavailableException('Penalty checkout is unavailable until Razorpay credentials are configured.');
        }

        return DB::transaction(function () use ($resident, $penalty, $method): array {
            $penalty = Penalty::query()->whereKey($penalty->id)->lockForUpdate()->firstOrFail();
            if ((int) $penalty->resident_id !== (int) $resident->id || $penalty->status !== 'approved' || $penalty->payment_status !== 'unpaid') {
                throw ValidationException::withMessages(['penalty' => 'This penalty is not eligible for payment.']);
            }
            $amount = round((float) $penalty->disciplinary_amount + (float) $penalty->repair_cost + (float) $penalty->late_fee_amount, 2);
            if ($amount <= 0) throw ValidationException::withMessages(['penalty' => 'This penalty has no payable balance.']);

            $existing = PaymentOrder::query()->where('resident_id', $resident->id)
                ->whereIn('status', [PaymentOrder::STATUS_PENDING, PaymentOrder::STATUS_PROCESSING])
                ->whereHas('items', fn ($query) => $query->where('penalty_id', $penalty->id))
                ->with('items')->latest()->first();
            if ($existing) {
                if (round((float) $existing->amount, 2) === $amount) {
                    return ['payment_order_id' => $existing->id, 'order_id' => $existing->provider_reference, 'amount' => (int) round($amount * 100), 'amount_formatted' => $amount, 'currency' => 'INR', 'key_id' => $this->razorpay->getKeyId(), 'name' => config('society.name') ?: config('app.name'), 'description' => 'Approved penalty', 'prefill' => ['name' => $resident->user?->name ?? '', 'email' => $resident->user?->email ?? '', 'contact' => $resident->user?->phone ?? '']];
                }
                $existing->update(['status' => PaymentOrder::STATUS_CANCELLED, 'verification_note' => 'Cancelled because the approved penalty amount changed.']);
            }

            $order = PaymentOrder::create(['resident_id' => $resident->id, 'flat_id' => $resident->flat_id, 'amount' => $amount, 'payment_method' => $method, 'status' => PaymentOrder::STATUS_PENDING, 'provider' => 'RAZORPAY', 'provider_reference' => 'TEMP-'.Str::upper(Str::random(12))]);
            PaymentOrderItem::create(['payment_order_id' => $order->id, 'penalty_id' => $penalty->id, 'amount' => $amount]);
            $gatewayOrder = $this->razorpay->createOrder($amount, 'PENALTY-'.$penalty->id.'-'.$order->id, ['payment_order_id' => $order->id, 'penalty_id' => $penalty->id, 'resident_id' => $resident->id]);
            $order->update(['provider_reference' => $gatewayOrder['id']]);
            $resident->loadMissing('user');
            return ['payment_order_id' => $order->id, 'order_id' => $gatewayOrder['id'], 'amount' => (int) round($amount * 100), 'amount_formatted' => $amount, 'currency' => 'INR', 'key_id' => $this->razorpay->getKeyId(), 'name' => config('society.name') ?: config('app.name'), 'description' => 'Approved penalty', 'prefill' => ['name' => $resident->user?->name ?? '', 'email' => $resident->user?->email ?? '', 'contact' => $resident->user?->phone ?? '']];
        });
    }

    private function refreshBillStatus(MaintenanceBill $bill): void
    {
        if ($bill->status === MaintenanceBill::STATUS_CANCELLED) {
            return;
        }

        $paid = (float) $bill->payments()
            ->where('status', MaintenancePayment::STATUS_COMPLETED)
            ->sum('amount');

        $bill->update([
            'status' => $paid >= (float) $bill->amount
                ? MaintenanceBill::STATUS_PAID
                : ($paid > 0 ? MaintenanceBill::STATUS_PARTIALLY_PAID : MaintenanceBill::STATUS_UNPAID),
        ]);
    }

    private function hasChargeComponents(MaintenanceBill $bill): bool
    {
        return collect([
            $bill->base_maintenance,
            $bill->water_charge,
            $bill->electricity_common_area_charge,
            $bill->parking_charge,
            $bill->other_charges,
            $bill->late_fee,
            $bill->discount,
        ])->contains(fn ($value) => (float) $value !== 0.0);
    }

    private function componentAmount(array $item, string $component): float
    {
        return (float) $item['bill']->{$component} * (float) $item['factor'];
    }

    /**
     * Creates a Razorpay checkout order for a single selected invoice.
     * Validates flat ownership, computes exact outstanding balance on the server,
     * and returns the checkout payload.
     *
     * @throws ValidationException
     */
    public function createRazorpayOrderForBill(Resident $resident, int $billId, string $method = MaintenancePayment::METHOD_UPI): array
    {
        return DB::transaction(function () use ($resident, $billId, $method): array {
            $bill = MaintenanceBill::query()
                ->where('id', $billId)
                ->where('flat_id', $resident->flat_id)
                ->whereNotIn('status', [MaintenanceBill::STATUS_CANCELLED])
                ->lockForUpdate()
                ->first();

            if (! $bill) {
                throw ValidationException::withMessages([
                    'maintenance_bill_id' => 'The selected invoice is invalid or does not belong to your flat.',
                ]);
            }

            $paid = (float) $bill->payments()
                ->where('status', MaintenancePayment::STATUS_COMPLETED)
                ->sum('amount');
            $outstanding = max(0, (float) $bill->amount - $paid);

            if ($outstanding <= 0.0) {
                throw ValidationException::withMessages([
                    'payment' => 'This invoice is already paid.',
                ]);
            }

            // Create internal PaymentOrder tracking record
            $order = PaymentOrder::create([
                'resident_id' => $resident->id,
                'flat_id' => $resident->flat_id,
                'amount' => $outstanding,
                'payment_method' => $method,
                'status' => PaymentOrder::STATUS_PENDING,
                'provider' => 'RAZORPAY',
                'provider_reference' => 'TEMP-' . Str::upper(Str::random(12)),
            ]);

            PaymentOrderItem::create([
                'payment_order_id' => $order->id,
                'maintenance_bill_id' => $bill->id,
                'amount' => $outstanding,
            ]);

            $receiptRef = sprintf('INV-%s-%06d', $bill->billing_month?->format('Ym') ?? 'DUE', $bill->id);
            $monthName = $bill->billing_month?->format('F Y') ?? 'Maintenance';

            $razorpayOrder = $this->razorpay->createOrder(
                $outstanding,
                $receiptRef,
                [
                    'payment_order_id' => $order->id,
                    'maintenance_bill_id' => $bill->id,
                    'resident_id' => $resident->id,
                    'flat_id' => $resident->flat_id,
                ]
            );

            $order->update([
                'provider_reference' => $razorpayOrder['id'],
            ]);

            $resident->loadMissing(['user', 'flat']);
            $societyName = config('society.name') ?: config('app.name', 'Kasliwal Marvel (West)');

            return [
                'order_id' => $razorpayOrder['id'],
                'amount' => (int) round($outstanding * 100),
                'amount_formatted' => $outstanding,
                'currency' => 'INR',
                'key_id' => $this->razorpay->getKeyId(),
                'name' => $societyName,
                'description' => "Maintenance · {$monthName}",
                'prefill' => [
                    'name' => $resident->user?->name ?? '',
                    'email' => $resident->user?->email ?? '',
                    'contact' => $resident->user?->phone ?? '',
                ],
                'notes' => [
                    'payment_order_id' => $order->id,
                    'maintenance_bill_id' => $bill->id,
                ],
                'payment_order_id' => $order->id,
                'maintenance_bill_id' => $bill->id,
                'is_single_invoice' => true,
            ];
        });
    }

    /**
     * Creates a Razorpay checkout order for all outstanding dues or selected dues.
     *
     * @throws ValidationException
     */
    public function createRazorpayOrderForAll(Resident $resident, string $method = MaintenancePayment::METHOD_UPI, ?array $billIds = null): array
    {
        return DB::transaction(function () use ($resident, $method, $billIds): array {
            if ($billIds !== null) {
                $ownedCount = MaintenanceBill::query()
                    ->where('flat_id', $resident->flat_id)
                    ->whereIn('id', $billIds)
                    ->count();

                if ($ownedCount !== count($billIds)) {
                    throw ValidationException::withMessages([
                        'maintenance_bill_ids' => 'One or more selected invoices do not belong to your flat.',
                    ]);
                }
            }

            $bills = MaintenanceBill::query()
                ->where('flat_id', $resident->flat_id)
                ->whereNotIn('status', [MaintenanceBill::STATUS_CANCELLED])
                ->when($billIds !== null, fn ($query) => $query->whereIn('id', $billIds))
                ->lockForUpdate()
                ->get();

            $items = $bills->map(function (MaintenanceBill $bill): array {
                $paid = (float) $bill->payments()
                    ->where('status', MaintenancePayment::STATUS_COMPLETED)
                    ->sum('amount');

                return [
                    'bill' => $bill,
                    'amount' => max(0, (float) $bill->amount - $paid),
                ];
            })->filter(fn (array $item) => $item['amount'] > 0)->values();

            if ($items->isEmpty()) {
                throw ValidationException::withMessages([
                    'payment' => 'There are no outstanding dues to pay.',
                ]);
            }

            $totalAmount = (float) $items->sum('amount');

            $order = PaymentOrder::create([
                'resident_id' => $resident->id,
                'flat_id' => $resident->flat_id,
                'amount' => $totalAmount,
                'payment_method' => $method,
                'status' => PaymentOrder::STATUS_PENDING,
                'provider' => 'RAZORPAY',
                'provider_reference' => 'TEMP-' . Str::upper(Str::random(12)),
            ]);

            foreach ($items as $item) {
                PaymentOrderItem::create([
                    'payment_order_id' => $order->id,
                    'maintenance_bill_id' => $item['bill']->id,
                    'amount' => $item['amount'],
                ]);
            }

            $receiptRef = sprintf('FULL-ORDER-%06d', $order->id);

            $razorpayOrder = $this->razorpay->createOrder(
                $totalAmount,
                $receiptRef,
                [
                    'payment_order_id' => $order->id,
                    'resident_id' => $resident->id,
                    'bill_count' => $items->count(),
                ]
            );

            $order->update([
                'provider_reference' => $razorpayOrder['id'],
            ]);

            $resident->loadMissing(['user', 'flat']);
            $societyName = config('society.name') ?: config('app.name', 'Kasliwal Marvel (West)');

            return [
                'order_id' => $razorpayOrder['id'],
                'amount' => (int) round($totalAmount * 100),
                'amount_formatted' => $totalAmount,
                'currency' => 'INR',
                'key_id' => $this->razorpay->getKeyId(),
                'name' => $societyName,
                'description' => "All Outstanding Maintenance Dues ({$items->count()} invoices)",
                'prefill' => [
                    'name' => $resident->user?->name ?? '',
                    'email' => $resident->user?->email ?? '',
                    'contact' => $resident->user?->phone ?? '',
                ],
                'notes' => [
                    'payment_order_id' => $order->id,
                    'bill_count' => $items->count(),
                ],
                'payment_order_id' => $order->id,
                'is_single_invoice' => false,
            ];
        });
    }

    /**
     * Verifies Razorpay payment signature and completes the payment atomically.
     * Idempotent: If already successful, returns order details without duplicating payments.
     *
     * @throws ValidationException
     */
    public function verifyAndReconcileRazorpayPayment(
        string $razorpayOrderId,
        string $razorpayPaymentId,
        string $signature,
        ?int $residentId = null
    ): array {
        return DB::transaction(function () use ($razorpayOrderId, $razorpayPaymentId, $signature, $residentId): array {
            $order = PaymentOrder::query()
                ->where('provider_reference', $razorpayOrderId)
                ->orWhere('id', is_numeric($razorpayOrderId) ? (int) $razorpayOrderId : 0)
                ->with(['items.bill', 'resident.user'])
                ->lockForUpdate()
                ->first();

            if (! $order) {
                throw ValidationException::withMessages([
                    'razorpay_order_id' => 'Payment order not found for the given reference.',
                ]);
            }

            if ($residentId !== null && (int) $order->resident_id !== $residentId) {
                throw ValidationException::withMessages([
                    'payment' => 'You do not have permission to verify this payment order.',
                ]);
            }

            // Idempotent: already marked successful
            if ($order->status === PaymentOrder::STATUS_SUCCESSFUL) {
                if ($order->gateway_payment_id !== $razorpayPaymentId) {
                    throw ValidationException::withMessages([
                        'razorpay_payment_id' => 'This order was already reconciled using a different payment reference.',
                    ]);
                }
                return [
                    'success' => true,
                    'message' => 'Payment has already been verified and processed.',
                    'payment_id' => $order->gateway_payment_id ?? $razorpayPaymentId,
                    'order' => $order->fresh(['items.bill', 'receipt']),
                ];
            }

            // Verify cryptographic signature
            $valid = $this->razorpay->verifyPaymentSignature($razorpayOrderId, $razorpayPaymentId, $signature);

            if (! $valid) {
                $order->update([
                    'status' => PaymentOrder::STATUS_FAILED,
                    'verification_note' => 'Signature verification failed.',
                ]);

                throw ValidationException::withMessages([
                    'signature' => 'Payment signature verification failed. Please contact society administration if amount was deducted.',
                ]);
            }

            if (round((float) $order->items->sum('amount'), 2) !== round((float) $order->amount, 2)) {
                throw ValidationException::withMessages([
                    'payment' => 'The payment order total does not match its recorded items.',
                ]);
            }

            // Record maintenance payments and update bill statuses to PAID
            $this->recordVerifiedOrderPayments($order, $razorpayPaymentId);

            $order->update([
                'status' => PaymentOrder::STATUS_SUCCESSFUL,
                'gateway_payment_id' => $razorpayPaymentId,
                'verification_note' => 'Verified via Razorpay signature.',
                'verified_at' => now(),
            ]);

            PaymentReceipt::firstOrCreate(
                ['payment_order_id' => $order->id],
                [
                    'receipt_number' => sprintf('REC-%s-%06d', now()->format('Ymd'), $order->id),
                    'amount' => $order->amount,
                    'currency' => 'INR',
                    'payment_method' => $order->payment_method ?: MaintenancePayment::METHOD_UPI,
                    'payment_reference' => $razorpayPaymentId,
                    'issued_at' => now(),
                ],
            );

            $order->loadMissing('resident.user');
            $order->resident?->user?->notify(new SocietyAlert(
                'payment_successful',
                'Payment successful',
                sprintf('Your maintenance payment of ₹%s was completed successfully.', number_format((float) $order->amount, 2)),
                ['payment_order_id' => $order->id, 'amount' => (float) $order->amount, 'payment_id' => $razorpayPaymentId],
            ));

            return [
                'success' => true,
                'message' => 'Payment verified and completed successfully.',
                'payment_id' => $razorpayPaymentId,
                'order' => $order->fresh(['items.bill', 'receipt']),
            ];
        });
    }
}

