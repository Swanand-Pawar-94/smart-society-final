<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Penalty extends Model
{
    protected $fillable = ['violation_report_id', 'resident_id', 'flat_id', 'disciplinary_amount', 'repair_cost', 'late_fee_amount', 'maintenance_bill_id', 'booking_id', 'late_fee_period', 'status', 'payment_status', 'due_date', 'decision_reason', 'decided_by_user_id', 'decided_at'];

    protected function casts(): array
    {
        return ['disciplinary_amount' => 'decimal:2', 'repair_cost' => 'decimal:2', 'late_fee_amount' => 'decimal:2', 'due_date' => 'date', 'decided_at' => 'datetime'];
    }

    public function report()
    {
        return $this->belongsTo(ViolationReport::class, 'violation_report_id');
    }

    public function resident()
    {
        return $this->belongsTo(Resident::class);
    }

    public function appeals()
    {
        return $this->hasMany(PenaltyAppeal::class);
    }

    public function paymentItems()
    {
        return $this->hasMany(PaymentOrderItem::class);
    }
}
