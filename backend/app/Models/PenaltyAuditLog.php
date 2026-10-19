<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PenaltyAuditLog extends Model
{
    protected $fillable = ['violation_report_id', 'user_id', 'action', 'from_status', 'to_status', 'reason', 'details'];

    protected function casts(): array
    {
        return ['details' => 'array'];
    }
}
