<?php

namespace Tests\Feature\Api;

use App\Models\User;
use App\Models\UserDeviceToken;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DeviceTokenTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_register_fcm_device_token(): void
    {
        $user = User::factory()->create([
            'role' => 'RESIDENT',
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->postJson('/api/device-tokens', [
                'fcm_token' => 'sample_fcm_token_123456789',
                'platform' => 'android',
                'device_id' => 'pixel_7_pro',
            ]);

        $response->assertCreated()
            ->assertJsonPath('data.fcm_token', 'sample_fcm_token_123456789')
            ->assertJsonPath('data.platform', 'android')
            ->assertJsonPath('data.is_active', true);

        $this->assertDatabaseHas('user_device_tokens', [
            'user_id' => $user->id,
            'fcm_token' => 'sample_fcm_token_123456789',
            'platform' => 'android',
            'is_active' => true,
        ]);
    }

    public function test_user_can_register_multiple_device_tokens(): void
    {
        $user = User::factory()->create([
            'role' => 'RESIDENT',
        ]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/device-tokens', [
                'fcm_token' => 'token_phone_1',
                'platform' => 'android',
            ])->assertCreated();

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/device-tokens', [
                'fcm_token' => 'token_tablet_2',
                'platform' => 'android',
            ])->assertCreated();

        $this->assertDatabaseCount('user_device_tokens', 2);
    }

    public function test_user_can_deactivate_token_on_logout(): void
    {
        $user = User::factory()->create([
            'role' => 'RESIDENT',
        ]);

        $token = UserDeviceToken::create([
            'user_id' => $user->id,
            'fcm_token' => 'token_to_remove',
            'platform' => 'android',
            'is_active' => true,
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->deleteJson('/api/device-tokens', [
                'fcm_token' => 'token_to_remove',
            ]);

        $response->assertOk();

        $this->assertDatabaseHas('user_device_tokens', [
            'id' => $token->id,
            'is_active' => false,
        ]);
    }

    public function test_registering_same_installation_for_another_account_deactivates_previous_owner(): void
    {
        $previousUser = User::factory()->create(['role' => 'RESIDENT']);
        $currentUser = User::factory()->create(['role' => 'RESIDENT']);
        UserDeviceToken::create([
            'user_id' => $previousUser->id,
            'fcm_token' => 'shared_installation_token',
            'platform' => 'android',
            'is_active' => true,
        ]);

        $this->actingAs($currentUser, 'sanctum')
            ->postJson('/api/device-tokens', [
                'fcm_token' => 'shared_installation_token',
                'platform' => 'android',
            ])->assertCreated();

        $this->assertDatabaseHas('user_device_tokens', [
            'user_id' => $previousUser->id,
            'fcm_token' => 'shared_installation_token',
            'is_active' => false,
        ]);
        $this->assertDatabaseHas('user_device_tokens', [
            'user_id' => $currentUser->id,
            'fcm_token' => 'shared_installation_token',
            'is_active' => true,
        ]);
    }
}
