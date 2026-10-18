<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;
use App\Notifications\Channels\FirebasePushChannel;

class SocietyAlert extends Notification
{
    use Queueable;

    public function __construct(
        private readonly string $type,
        private readonly string $title,
        private readonly string $message,
        private readonly array $context = [],
    ) {}

    public function via(object $notifiable): array
    {
        return ['database', FirebasePushChannel::class];
    }

    public function toArray(object $notifiable): array
    {
        return [
            'type' => $this->type,
            'title' => $this->title,
            'message' => $this->message,
            ...$this->context,
        ];
    }
}
