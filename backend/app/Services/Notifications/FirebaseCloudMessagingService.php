<?php

namespace App\Services\Notifications;

use App\Models\User;
use App\Models\UserDeviceToken;
use App\Models\Visitor;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class FirebaseCloudMessagingService
{
    private const FCM_V1_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
    private const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';
    private const ACCESS_TOKEN_CACHE_KEY = 'fcm_v1_access_token';
    // Cache access token for 55 minutes (Google tokens are valid for 60 min)
    private const ACCESS_TOKEN_TTL_SECONDS = 3300;

    /**
     * Send high-priority visitor approval push notification with sound and vibration.
     */
    public function sendVisitorApprovalNotification(User $residentUser, Visitor $visitor): array
    {
        $tokens = UserDeviceToken::query()
            ->where('user_id', $residentUser->id)
            ->where('is_active', true)
            ->get();

        if ($tokens->isEmpty()) {
            Log::info('[FCM] No active device tokens found for resident', [
                'user_id' => $residentUser->id,
            ]);
            return ['status' => 'NO_TOKENS', 'sent' => 0];
        }

        // Ensure flat is loaded so the notification body is complete
        if (! $visitor->relationLoaded('flat')) {
            $visitor->load('flat');
        }

        $flatNumber = (string) ($visitor->flat?->flat_number ?? 'N/A');
        $building   = (string) ($visitor->flat?->building ?? '');

        $title = 'Visitor Approval Request';
        $body  = sprintf(
            '%s is requesting entry to Flat %s%s.',
            $visitor->visitor_name,
            $flatNumber,
            $building ? " - Building {$building}" : ''
        );

        $payloadData = [
            'notification_type' => 'visitor_approval_request',
            'visitor_id'        => (string) $visitor->id,
            'visitor_name'      => (string) $visitor->visitor_name,
            'visitor_type'      => (string) ($visitor->visitor_type ?? 'GUEST'),
            'flat_id'           => (string) $visitor->flat_id,
            'flat_number'       => $flatNumber,
            'building'          => $building,
            'resident_id'       => (string) $visitor->resident_id,
            'requested_at'      => now()->toIso8601String(),
            'click_action'      => 'FLUTTER_NOTIFICATION_CLICK',
        ];

        $results = [];
        foreach ($tokens as $tokenRecord) {
            $result = $this->sendToToken($tokenRecord->fcm_token, $title, $body, $payloadData);
            $results[] = $result;

            if (in_array($result['status'] ?? '', ['UNREGISTERED', 'INVALID_TOKEN'], true)) {
                $tokenRecord->update(['is_active' => false]);
                Log::info('[FCM] Deactivated invalid/unregistered token', ['token_id' => $tokenRecord->id]);
            }
        }

        $successCount = count(array_filter($results, fn ($r) => ($r['status'] ?? '') === 'ACCEPTED'));
        Log::info('[FCM] Notification dispatch summary', [
            'visitor_id'    => $visitor->id,
            'user_id'       => $residentUser->id,
            'tokens_found'  => $tokens->count(),
            'accepted_by_fcm' => $successCount,
        ]);

        return ['status' => 'PROCESSED', 'results' => $results];
    }

    /**
     * Send an FCM push notification to ALL active devices belonging to a user.
     *
     * This is the generic entry point for any notification event.
     * Failures are logged but never propagated — caller's workflow must not break.
     *
     * @param  array<string,string>  $data  Safe key-value pairs for Flutter navigation. Never include credentials.
     */
    public function sendToUser(
        User $user,
        string $title,
        string $body,
        string $type,
        array $data = [],
    ): array {
        $tokens = UserDeviceToken::query()
            ->where('user_id', $user->id)
            ->where('is_active', true)
            ->get();

        if ($tokens->isEmpty()) {
            Log::info('[FCM] sendToUser — no active device tokens', [
                'user_id' => $user->id,
                'type'    => $type,
            ]);

            return ['status' => 'NO_TOKENS', 'sent' => 0];
        }

        // Build payload — type always present so Flutter can route the tap correctly
        $payloadData = array_merge([
            'type'              => $type,
            'notification_type' => $type,
        ], $data);

        $results = [];
        foreach ($tokens as $tokenRecord) {
            $result    = $this->sendToToken($tokenRecord->fcm_token, $title, $body, $payloadData);
            $results[] = $result;

            // Deactivate stale tokens so we do not attempt them again
            if (in_array($result['status'] ?? '', ['UNREGISTERED', 'INVALID_TOKEN'], true)) {
                $tokenRecord->update(['is_active' => false]);
                Log::info('[FCM] Deactivated stale token', ['token_id' => $tokenRecord->id, 'type' => $type]);
            }
        }

        $accepted = count(array_filter($results, fn ($r) => ($r['status'] ?? '') === 'ACCEPTED'));

        Log::info('[FCM] sendToUser complete', [
            'user_id'   => $user->id,
            'type'      => $type,
            'tokens'    => $tokens->count(),
            'accepted_by_fcm' => $accepted,
        ]);

        return ['status' => 'PROCESSED', 'results' => $results, 'accepted_by_fcm' => $accepted];
    }

    /**
     * Send a single FCM message via the HTTP v1 API using a service account.
     */
    public function sendToToken(string $fcmToken, string $title, string $body, array $data = []): array
    {
        $projectId = config('services.firebase.project_id');

        if (empty($projectId)) {
            Log::warning('[FCM] FIREBASE_PROJECT_ID is not set in .env');
            return ['status' => 'CONFIG_ERROR', 'message' => 'FIREBASE_PROJECT_ID not configured'];
        }

        try {
            $accessToken = $this->getAccessToken();
        } catch (\Throwable $e) {
            Log::error('[FCM] Failed to obtain OAuth2 access token', [
                'exception' => get_class($e),
            ]);
            return ['status' => 'AUTH_ERROR'];
        }

        $fcmUrl = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";

        $payload = [
            'message' => [
                'token'        => $fcmToken,
                'notification' => [
                    'title' => $title,
                    'body'  => $body,
                ],
                'android' => [
                    'priority'     => 'high',
                    'notification' => [
                        'channel_id'            => 'visitor_requests',
                        'sound'                 => 'default',
                        'notification_priority' => 'PRIORITY_MAX',
                        'default_sound'         => true,
                        'default_vibrate_timings' => true,
                        'visibility'            => 'PUBLIC',
                    ],
                ],
                'data' => $data,
            ],
        ];

        try {
            $response = Http::connectTimeout(5)->timeout(10)->withToken($accessToken)
                ->acceptJson()
                ->post($fcmUrl, $payload);

            $responseData = $response->json();

            if ($response->successful()) {
                Log::info('[FCM] Message accepted by FCM HTTP v1 API', [
                    'message_name' => $responseData['name'] ?? null,
                ]);
                return ['status' => 'ACCEPTED', 'response' => $responseData];
            }

            $errorCode   = $responseData['error']['status'] ?? 'UNKNOWN';
            $errorMessage = $responseData['error']['message'] ?? '';

            Log::error('[FCM] HTTP v1 API returned error', [
                'http_status'   => $response->status(),
                'error_status'  => $errorCode,
                'error_message' => $errorCode,
            ]);

            // Map known FCM error codes for token cleanup
            $status = match ($errorCode) {
                'UNREGISTERED'   => 'UNREGISTERED',
                'INVALID_ARGUMENT' => str_contains(strtolower($errorMessage), 'registration token')
                    ? 'INVALID_TOKEN'
                    : 'INVALID_ARGUMENT',
                default => 'GATEWAY_ERROR',
            };

            return ['status' => $status, 'http_status' => $response->status()];

        } catch (\Throwable $e) {
            Log::error('[FCM] Exception during HTTP v1 API dispatch', [
                'class' => get_class($e),
            ]);
            return ['status' => 'EXCEPTION'];
        }
    }

    /**
     * Obtain (or retrieve from cache) a Google OAuth2 access token
     * using the Firebase service account private key via JWT Bearer flow.
     */
    private function getAccessToken(): string
    {
        return Cache::remember(
            self::ACCESS_TOKEN_CACHE_KEY,
            self::ACCESS_TOKEN_TTL_SECONDS,
            function (): string {
                $credentials = $this->loadCredentials();
                $jwt         = $this->buildJwt($credentials);
                return $this->exchangeJwtForToken($jwt);
            }
        );
    }

    /**
     * Load the service account JSON from the path specified in .env.
     */
    private function loadCredentials(): array
    {
        $path = config('services.firebase.credentials_file');

        if (empty($path)) {
            throw new \RuntimeException(
                'FIREBASE_CREDENTIALS_FILE is not set in .env. ' .
                'Download it from Firebase Console → Project Settings → Service Accounts → Generate New Private Key.'
            );
        }

        // Support paths relative to the Laravel base directory
        if (! str_starts_with($path, '/') && ! preg_match('/^[A-Za-z]:/', $path)) {
            $path = base_path($path);
        }

        if (! file_exists($path)) {
            throw new \RuntimeException(
                "Firebase credentials file not found at: {$path}. " .
                'Download it from Firebase Console → Service Accounts.'
            );
        }

        $json = file_get_contents($path);
        $credentials = json_decode($json, true);

        if (! is_array($credentials) || empty($credentials['private_key']) || empty($credentials['client_email'])) {
            throw new \RuntimeException(
                'Firebase credentials file is invalid or missing required fields (private_key, client_email).'
            );
        }

        return $credentials;
    }

    /**
     * Build a signed RS256 JWT for the Google OAuth2 token endpoint.
     *
     * Google OAuth2 JWT flow:
     *   https://developers.google.com/identity/protocols/oauth2/service-account#jwt-auth
     */
    private function buildJwt(array $credentials): string
    {
        $now = time();

        $header = $this->base64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));

        $claims = $this->base64url(json_encode([
            'iss'   => $credentials['client_email'],
            'sub'   => $credentials['client_email'],
            'aud'   => self::OAUTH_TOKEN_URL,
            'iat'   => $now,
            'exp'   => $now + 3600,
            'scope' => self::FCM_V1_SCOPE,
        ]));

        $signingInput = "{$header}.{$claims}";
        $signature    = '';

        $success = openssl_sign($signingInput, $signature, $credentials['private_key'], 'SHA256');

        if (! $success) {
            throw new \RuntimeException(
                'Failed to sign JWT with the service account private key. ' .
                'Ensure the credentials file contains a valid RSA private key.'
            );
        }

        return "{$signingInput}." . $this->base64url($signature);
    }

    /**
     * Exchange the signed JWT for a short-lived Google OAuth2 access token.
     */
    private function exchangeJwtForToken(string $jwt): string
    {
        $response = Http::connectTimeout(5)->timeout(10)->asForm()->post(self::OAUTH_TOKEN_URL, [
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ]);

        if (! $response->successful()) {
            throw new \RuntimeException('Google OAuth2 token exchange failed.');
        }

        $token = $response->json('access_token');

        if (empty($token)) {
            throw new \RuntimeException('Google OAuth2 response did not contain an access token.');
        }

        Log::info('[FCM] OAuth2 access token obtained successfully (cached for 55 min)');

        return $token;
    }

    /**
     * Base64 URL-safe encode (no padding).
     */
    private function base64url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}
