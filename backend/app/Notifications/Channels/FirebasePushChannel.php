<?php

namespace App\Notifications\Channels;

use App\Models\User;
use App\Services\Notifications\FirebaseCloudMessagingService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/** Deliver a persisted Laravel notification to the user's active FCM devices. */
class FirebasePushChannel
{
    public function send(User $notifiable, object $notification): void
    {
        if (! method_exists($notification, 'toArray')) {
            return;
        }

        $data = $notification->toArray($notifiable);
        $title = (string) ($data['title'] ?? 'Nivora notification');
        $body = (string) ($data['message'] ?? 'You have a new society notification.');
        $type = (string) ($data['type'] ?? 'society_update');
        $notificationId = (string) ($notification->id ?? '');
        $payload = array_map(
            static fn (mixed $value): string => is_scalar($value)
                ? (string) $value
                : (json_encode($value, JSON_UNESCAPED_SLASHES) ?: ''),
            $data,
        );
        $payload['type'] = $type;
        $payload['notification_type'] = $type;
        $payload['notification_id'] = $notificationId;
        $payload['title'] = $title;
        $payload['body'] = $body;

        // This channel follows the database channel in via(), so the row is
        // created first. Defer network I/O until an enclosing transaction
        // commits and never allow an FCM outage to roll back business work.
        DB::afterCommit(static function () use ($notifiable, $title, $body, $type, $payload): void {
            try {
                app(FirebaseCloudMessagingService::class)->sendToUser(
                    $notifiable,
                    $title,
                    $body,
                    $type,
                    $payload,
                );
            } catch (\Throwable $exception) {
                Log::warning('[FCM] Push notification dispatch failed', [
                    'user_id' => $notifiable->id,
                    'type' => $type,
                    'exception' => get_class($exception),
                ]);
            }
        });
    }
}
