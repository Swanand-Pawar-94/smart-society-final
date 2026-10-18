<?php

namespace App\Notifications;

use App\Models\Visitor;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;
use App\Notifications\Channels\FirebasePushChannel;

class VisitorAwaitingApproval extends Notification
{
    use Queueable;

    public function __construct(private readonly Visitor $visitor) {}

    public function via(object $notifiable): array
    {
        return ['database', FirebasePushChannel::class];
    }

    public function toArray(object $notifiable): array
    {
        $flatNumber = $this->visitor->flat?->flat_number;
        $building = $this->visitor->flat?->building;
        $location = trim(($flatNumber ? "Flat {$flatNumber}" : '').($building ? ", {$building}" : ''));
        if (empty($location)) {
            $location = 'your unit';
        }

        return [
            'type' => 'visitor_request',
            'title' => 'Visitor Request',
            'message' => sprintf('%s is requesting entry to %s.', $this->visitor->visitor_name, $location),
            'visitor_id' => $this->visitor->id,
            'visitor_request_id' => $this->visitor->id,
            'visitor_name' => $this->visitor->visitor_name,
            'visitor_type' => $this->visitor->visitor_type ?? 'GUEST',
            'flat_id' => $this->visitor->flat_id,
            'flat_number' => $flatNumber,
            'building' => $building,
            'purpose' => $this->visitor->purpose,
            'approval_status' => $this->visitor->approval_status ?? 'PENDING',
            'entry_status' => $this->visitor->entry_status ?? 'WAITING',
            'requested_at' => now()->toISOString(),
            'created_at' => now()->toISOString(),
        ];
    }
}
