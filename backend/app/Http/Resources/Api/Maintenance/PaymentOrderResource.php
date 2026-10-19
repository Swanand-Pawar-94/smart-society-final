<?php

namespace App\Http\Resources\Api\Maintenance;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentOrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'resident_id' => $this->resident_id,
            'flat_id' => $this->flat_id,
            'amount' => $this->amount,
            'payment_method' => $this->payment_method,
            'status' => $this->status,
            'provider' => $this->provider,
            'provider_reference' => $this->provider_reference,
            'gateway_payment_id' => $this->gateway_payment_id,
            'verification_note' => $this->verification_note,
            'verified_at' => $this->verified_at?->toISOString(),
            'resident' => $this->whenLoaded('resident', fn () => [
                'id' => $this->resident->id,
                'name' => $this->resident->user?->name,
            ]),
            'flat' => $this->whenLoaded('flat', fn () => [
                'id' => $this->flat->id,
                'flat_number' => $this->flat->flat_number,
                'building' => $this->flat->building,
            ]),
            'items' => $this->whenLoaded('items', fn () => $this->items->map(fn ($item) => [
                'id' => $item->id,
                'maintenance_bill_id' => $item->maintenance_bill_id,
                'penalty_id' => $item->penalty_id,
                'amount' => $item->amount,
                'bill' => $item->relationLoaded('bill') && $item->bill ? [
                    'billing_month' => $item->bill->billing_month?->toDateString(),
                    'due_date' => $item->bill->due_date?->toDateString(),
                    'status' => $item->bill->status,
                ] : null,
                'penalty' => $item->relationLoaded('penalty') && $item->penalty ? [
                    'id' => $item->penalty->id,
                    'status' => $item->penalty->status,
                    'payment_status' => $item->penalty->payment_status,
                    'disciplinary_amount' => $item->penalty->disciplinary_amount,
                    'late_fee_amount' => $item->penalty->late_fee_amount,
                    'repair_cost' => $item->penalty->repair_cost,
                ] : null,
            ])),
            'payments' => MaintenancePaymentResource::collection($this->whenLoaded('maintenancePayments')),
            'receipt' => $this->whenLoaded('receipt', fn () => new PaymentReceiptResource($this->receipt)),
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
