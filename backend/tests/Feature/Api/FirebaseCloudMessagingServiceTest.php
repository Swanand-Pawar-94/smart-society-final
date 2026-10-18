<?php

namespace Tests\Feature\Api;

use App\Models\User;
use App\Models\UserDeviceToken;
use App\Services\Notifications\FirebaseCloudMessagingService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class FirebaseCloudMessagingServiceTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Cache::flush();
        config(['services.firebase.project_id' => 'test-project']);
        // The access token is a test double; HTTP calls below are always faked.
        Cache::put('fcm_v1_access_token', 'mock-access-token', now()->addMinutes(55));
    }

    public function test_http_v1_payload_contains_structured_notification_data(): void
    {
        Http::fake([
            'fcm.googleapis.com/v1/projects/test-project/messages:send' => Http::response(['name' => 'projects/test-project/messages/123'], 200),
        ]);

        $result = app(FirebaseCloudMessagingService::class)->sendToToken(
            'unit-test-device-token',
            'New notice',
            'A notice was published.',
            ['type' => 'notice_published', 'notification_id' => 'notice-123', 'notice_id' => '42'],
        );

        $this->assertSame('ACCEPTED', $result['status'], json_encode($result));
        Http::assertSent(fn (Request $request): bool => str_contains($request->url(), '/messages:send')
            && $request['message']['notification']['title'] === 'New notice'
            && $request['message']['data']['type'] === 'notice_published'
            && $request['message']['data']['notification_id'] === 'notice-123'
            && $request['message']['data']['notice_id'] === '42');
    }

    public function test_confirmed_unregistered_device_token_is_deactivated(): void
    {
        $user = User::factory()->create(['role' => 'RESIDENT']);
        $device = UserDeviceToken::create([
            'user_id' => $user->id,
            'fcm_token' => 'confirmed-unregistered-token',
            'platform' => 'android',
            'is_active' => true,
        ]);

        Http::fake([
            'fcm.googleapis.com/v1/projects/test-project/messages:send' => Http::response([
                'error' => ['status' => 'UNREGISTERED', 'message' => 'Token is no longer registered.'],
            ], 404),
        ]);

        $result = app(FirebaseCloudMessagingService::class)->sendToUser(
            $user,
            'Notice',
            'Notice content',
            'notice_published',
        );

        $this->assertSame('UNREGISTERED', $result['results'][0]['status'], json_encode($result));
        $this->assertDatabaseHas('user_device_tokens', ['id' => $device->id, 'is_active' => false]);
    }
}
