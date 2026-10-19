<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PenaltyAppeal extends Model
{
    protected $fillable = ['penalty_id', 'resident_id', 'reason', 'status', 'decision_reason', 'decided_by_user_id', 'decided_at'];

    protected function casts(): array
    {
        return ['decided_at' => 'datetime'];
    }

    public function penalty()
    {
        return $this->belongsTo(Penalty::class);
    }
}
