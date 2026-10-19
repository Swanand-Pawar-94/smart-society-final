<?php

namespace App\Http\Controllers\Api\Maintenance;

use App\Contracts\Payments\PaymentGateway;
use App\Exceptions\PaymentGatewayUnavailableException;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\Maintenance\PaymentOrderResource;
use App\Http\Resources\Api\Maintenance\PaymentReceiptResource;
use App\Models\MaintenancePayment;
use App\Models\PaymentOrder;
use App\Services\Maintenance\PaymentOrderService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class ResidentPaymentOrderController extends Controller
{
    public function __construct(private readonly PaymentOrderService $orders) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', PaymentOrder::class);
        $resident = $request->user()->resident()->firstOrFail();

        $orders = PaymentOrder::query()
            ->with(['items.bill:id,billing_month,due_date', 'items.penalty'])
            ->where('resident_id', $resident->id)
            ->latest()
            ->paginate();

        return PaymentOrderResource::collection($orders);
    }

    public function summary(Request $request): JsonResponse
    {
        Gate::authorize('viewAny', PaymentOrder::class);
        $billIds = $request->query('maintenance_bill_ids');
        if (is_string($billIds)) {
            $billIds = array_filter(array_map('intval', explode(',', $billIds)));
        }

        return response()->json([
            'data' => $this->orders->summary(
                $this->currentResident($request),
                is_array($billIds) && ! empty($billIds) ? array_values($billIds) : null,
            ),
        ]);
    }

    public function show(Request $request, PaymentOrder $paymentOrder): PaymentOrderResource
    {
        Gate::authorize('view', $paymentOrder);
        $this->currentResident($request);

        return new PaymentOrderResource($paymentOrder->load(['items.bill', 'items.penalty', 'maintenancePayments.bill', 'receipt']));
    }

    public function store(Request $request): JsonResponse
    {
        Gate::authorize('create', PaymentOrder::class);
        $data = $request->validate([
            'payment_method' => ['required', Rule::in(MaintenancePayment::paymentMethods())],
            'maintenance_bill_ids' => ['nullable', 'array', 'min:1'],
            'maintenance_bill_ids.*' => ['integer', 'distinct', 'exists:maintenance_bills,id'],
        ]);
        $resident = $this->currentResident($request);
        $order = $this->orders->initiateFullPayment(
            $resident,
            $data['payment_method'],
            $data['maintenance_bill_ids'] ?? null,
        );

        return (new PaymentOrderResource($order))
            ->response()
            ->setStatusCode(201);
    }

    public function cancel(Request $request, PaymentOrder $paymentOrder): PaymentOrderResource
    {
        Gate::authorize('cancel', $paymentOrder);
        $this->currentResident($request);

        return new PaymentOrderResource($this->orders->cancelByResident($paymentOrder));
    }

    public function confirmDemo(Request $request, PaymentOrder $paymentOrder): JsonResponse
    {
        if (config('app.payment_mode', 'live') !== 'demo') {
            return response()->json([
                'message' => 'Demo payment confirmation is not enabled on this server.',
                'code' => 'DEMO_MODE_DISABLED',
            ], 503);
        }

        Gate::authorize('view', $paymentOrder);
        $resident = $this->currentResident($request);

        $order = $this->orders->confirmDemo($paymentOrder, $resident->id);

        return (new PaymentOrderResource($order))->response();
    }

    public function checkout(Request $request, PaymentOrder $paymentOrder, PaymentGateway $gateway): JsonResponse
    {
        Gate::authorize('view', $paymentOrder);
        $this->currentResident($request);

        if (! in_array($paymentOrder->status, [PaymentOrder::STATUS_PENDING, PaymentOrder::STATUS_PROCESSING], true)) {
            throw ValidationException::withMessages([
                'payment' => 'Checkout is available only for a pending payment order.',
            ]);
        }

        try {
            return response()->json(['data' => $gateway->createCheckout($paymentOrder)]);
        } catch (PaymentGatewayUnavailableException $exception) {
            return response()->json([
                'message' => $exception->getMessage(),
                'code' => 'PAYMENT_GATEWAY_NOT_CONFIGURED',
            ], 503);
        }
    }

    public function receipt(Request $request, PaymentOrder $paymentOrder): PaymentReceiptResource
    {
        Gate::authorize('view', $paymentOrder);
        $this->currentResident($request);
        $receipt = $paymentOrder->receipt;

        if (! $receipt) {
            throw ValidationException::withMessages([
                'receipt' => 'A receipt is available only after payment verification.',
            ]);
        }

        return new PaymentReceiptResource($receipt->load('paymentOrder'));
    }

    private function currentResident(Request $request)
    {
        return $request->user()->resident()->firstOrFail();
    }
}
