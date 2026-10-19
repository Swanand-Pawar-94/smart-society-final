<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ViolationReport extends Model
{
    protected $fillable = [
        'rule_id', 'category', 'violation_type', 'flat_id', 'resident_id', 'vehicle_slot_id',
        'maintenance_bill_id', 'booking_id', 'reported_by_user_id', 'incident_at', 'location',
        'description', 'incident_fingerprint', 'status',
    ];

    protected function casts(): array
    {
        return ['incident_at' => 'datetime'];
    }

    public function rule()
    {
        return $this->belongsTo(PenaltyRule::class, 'rule_id');
    }

    public function flat()
    {
        return $this->belongsTo(Flat::class);
    }

    public function resident()
    {
        return $this->belongsTo(Resident::class);
    }

    public function reporter()
    {
        return $this->belongsTo(User::class, 'reported_by_user_id');
    }

    public function evidence()
    {
        return $this->hasMany(ViolationEvidence::class);
    }

    public function penalty()
    {
        return $this->hasOne(Penalty::class);
    }

    public function auditLogs()
    {
        return $this->hasMany(PenaltyAuditLog::class);
    }
}
