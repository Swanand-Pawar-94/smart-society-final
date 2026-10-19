<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PenaltyRule extends Model
{
    protected $fillable = ['category', 'violation_type', 'description', 'minimum_amount', 'maximum_amount', 'late_fee_amount', 'grace_period_days', 'requires_evidence', 'active', 'updated_by_user_id'];

    protected function casts(): array
    {
        return ['minimum_amount' => 'decimal:2', 'maximum_amount' => 'decimal:2', 'late_fee_amount' => 'decimal:2', 'requires_evidence' => 'boolean', 'active' => 'boolean'];
    }
}
