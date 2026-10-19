<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PaymentOrderItem extends Model
{
    protected $fillable = ['payment_order_id', 'maintenance_bill_id', 'penalty_id', 'amount'];

    protected function casts(): array
    {
        return ['amount' => 'decimal:2'];
    }

    public function order()
    {
        return $this->belongsTo(PaymentOrder::class, 'payment_order_id');
    }

    public function bill()
    {
        return $this->belongsTo(MaintenanceBill::class, 'maintenance_bill_id');
    }

    public function penalty()
    {
        return $this->belongsTo(Penalty::class);
    }
}
