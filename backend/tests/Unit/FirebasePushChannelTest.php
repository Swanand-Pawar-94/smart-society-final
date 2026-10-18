<?php

namespace Tests\Unit;

use App\Models\User;
use App\Notifications\Channels\FirebasePushChannel;
use App\Notifications\SocietyAlert;
use App\Services\Notifications\FirebaseCloudMessagingService;
use Illuminate\Support\Facades\DB;
use Mockery;
use Tests\TestCase;

class FirebasePushChannelTest extends TestCase
{
    public function test_push_is_scheduled_after_commit_and_failure_does_not_escape(): void
    {
        $user = new User;
        $user->id = 27;
        $notification = new SocietyAlert(
            'complaint_status_changed',
            'Complaint updated',
            'Your complaint is now resolved.',
            ['complaint_id' => 9],
        );
        $notification->id = 'notification-27';

        $afterCommit = null;
        DB::shouldReceive('afterCommit')->once()->andReturnUsing(function (callable $callback) use (&$afterCommit): void {
            $afterCommit = $callback;
        });

        $sender = Mockery::mock(FirebaseCloudMessagingService::class);
        $sender->shouldReceive('sendToUser')
            ->once()
            ->withArgs(fn ($recipient, $title, $body, $type, $data): bool => $recipient->id === 27
                && $title === 'Complaint updated'
                && $body === 'Your complaint is now resolved.'
                && $type === 'complaint_status_changed'
                && $data['notification_id'] === 'notification-27'
                && $data['complaint_id'] === '9')
            ->andThrow(new \RuntimeException('Simulated Firebase failure'));
        $this->app->instance(FirebaseCloudMessagingService::class, $sender);

        app(FirebasePushChannel::class)->send($user, $notification);
        $this->assertNotNull($afterCommit);

        // The committed business operation remains successful if Firebase is
        // unavailable when the after-commit callback runs.
        $afterCommit();
        $this->assertTrue(true);
    }
}
