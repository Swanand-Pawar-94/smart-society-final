<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ViolationEvidence extends Model
{
    protected $fillable = ['violation_report_id', 'appeal_id', 'uploaded_by_user_id', 'disk', 'path', 'original_name', 'mime_type', 'size_bytes'];

    public function report()
    {
        return $this->belongsTo(ViolationReport::class, 'violation_report_id');
    }
}
