<?php

namespace App\Http\Controllers\Api\Maintenance;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Maintenance\TransitionPaymentOrderRequest;
use App\Http\Resources\Api\Maintenance\PaymentOrderResource;
use App\Http\Resources\Api\Maintenance\PaymentReceiptResource;
use App\Models\PaymentOrder;
use App\Services\Maintenance\PaymentOrderService;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\ValidationException;

class AdminPaymentOrderController extends Controller
{
    public function __construct(private readonly PaymentOrderService $orders) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', PaymentOrder::class);

        $orders = PaymentOrder::query()
            ->with(['resident.user', 'flat', 'items.bill', 'items.penalty'])
            ->when($request->query('status'), fn ($query, string $status) => $query->where('status', $status))
            ->latest()
            ->paginate();

        return PaymentOrderResource::collection($orders);
    }

    public function show(PaymentOrder $paymentOrder): PaymentOrderResource
    {
        Gate::authorize('view', $paymentOrder);

        return new PaymentOrderResource($paymentOrder->load([
            'resident.user', 'flat', 'items.bill', 'items.penalty', 'maintenancePayments.bill', 'receipt',
        ]));
    }

    public function transition(TransitionPaymentOrderRequest $request, PaymentOrder $paymentOrder): PaymentOrderResource
    {
        Gate::authorize('transition', $paymentOrder);
        if ($request->validated('status') === PaymentOrder::STATUS_SUCCESSFUL
            && $paymentOrder->items()->whereNotNull('penalty_id')->exists()) {
            throw ValidationException::withMessages([
                'status' => 'Penalty orders can only be completed through verified gateway callbacks.',
            ]);
        }

        return new PaymentOrderResource(
            $this->orders->transition($paymentOrder, $request->validated()),
        );
    }

    public function receipt(PaymentOrder $paymentOrder): PaymentReceiptResource
    {
        Gate::authorize('view', $paymentOrder);
        $receipt = $paymentOrder->receipt;

        if (! $receipt) {
            throw ValidationException::withMessages([
                'receipt' => 'A receipt is available only after payment verification.',
            ]);
        }

        return new PaymentReceiptResource($receipt->load('paymentOrder'));
    }
}
