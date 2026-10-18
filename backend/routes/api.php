<?php

use App\Http\Controllers\Api\Amenities\AmenityController;
use App\Http\Controllers\Api\Authentication\AuthController;
use App\Http\Controllers\Api\Complaints\ComplaintController;
use App\Http\Controllers\Api\Dashboard\AdminDashboardController;
use App\Http\Controllers\Api\Dashboard\ResidentDashboardController;
use App\Http\Controllers\Api\Dashboard\SecurityDashboardController;
use App\Http\Controllers\Api\Dashboard\StaffDashboardController;
use App\Http\Controllers\Api\Flats\FlatController;
use App\Http\Controllers\Api\Maintenance\AdminMaintenanceBillController;
use App\Http\Controllers\Api\Maintenance\AdminMaintenancePaymentController;
use App\Http\Controllers\Api\Maintenance\AdminPaymentOrderController;
use App\Http\Controllers\Api\Maintenance\ResidentMaintenanceBillController;
use App\Http\Controllers\Api\Maintenance\ResidentMaintenanceController;
use App\Http\Controllers\Api\Maintenance\ResidentMaintenancePaymentController;
use App\Http\Controllers\Api\Maintenance\ResidentPaymentOrderController;
use App\Http\Controllers\Api\Maintenance\ResidentTransactionHistoryController;
use App\Http\Controllers\Api\Messaging\MessagingController;
use App\Http\Controllers\Api\Notices\NoticeController;
use App\Http\Controllers\Api\Notifications\NotificationController;
use App\Http\Controllers\Api\Options\SelectionOptionsController;
use App\Http\Controllers\Api\Parcels\ParcelController;
use App\Http\Controllers\Api\Parking\ParkingController;
use App\Http\Controllers\Api\Payment\PaymentGatewayController;
use App\Http\Controllers\Api\Reports\AdminReportController;
use App\Http\Controllers\Api\Residents\ResidentController;
use App\Http\Controllers\Api\Staff\AdminStaffMemberController;
use App\Http\Controllers\Api\Visitors\AdminVisitorController;
use App\Http\Controllers\Api\Visitors\ResidentVisitorController;
use App\Http\Controllers\Api\Visitors\SecurityVisitorController;
use App\Http\Controllers\Api\Visitors\VisitorRequestController;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('health', function () {
    try {
        $database = DB::connection()->getDatabaseName();
    } catch (\Throwable $e) {
        $database = 'disconnected';
    }

    return response()->json([
        'status'    => 'ok',
        'message'   => 'Smart Society API is running',
        'service'   => 'Smart Society API',
        'timestamp' => now()->toISOString(),
        'database'  => $database,
    ]);
});

// Simple ping endpoint — test this from the Android phone browser first
// URL: http://192.168.29.18:8000/api/ping
Route::get('ping', function () {
    return response()->json([
        'success'        => true,
        'message'        => 'Phone can reach Laravel server',
        'server_time'    => now()->toISOString(),
        'server_ip'      => request()->server('SERVER_ADDR'),
        'client_ip'      => request()->ip(),
        'host_header'    => request()->header('host'),
    ]);
});

// Debug info — shows exactly what the server sees about the incoming request
Route::get('debug-info', function () {
    return response()->json([
        'server_addr'    => request()->server('SERVER_ADDR'),
        'server_port'    => request()->server('SERVER_PORT'),
        'client_ip'      => request()->ip(),
        'forwarded_for'  => request()->header('X-Forwarded-For'),
        'host'           => request()->header('host'),
        'user_agent'     => request()->header('User-Agent'),
        'request_uri'    => request()->server('REQUEST_URI'),
    ]);
});


Route::prefix('auth')->group(function (): void {
    Route::post('login', [AuthController::class, 'login']);
    Route::post('register', [AuthController::class, 'register']);
    Route::post('forgot-password', [AuthController::class, 'forgotPassword']);
    Route::post('reset-password', [AuthController::class, 'resetPassword']);

    Route::middleware('auth:sanctum')->group(function (): void {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
        Route::patch('profile', [AuthController::class, 'updateProfile']);
    });
});

Route::middleware('auth:sanctum')->group(function (): void {
    // FCM device token registration (canonical endpoint)
    Route::post('device-tokens', [\App\Http\Controllers\Api\Devices\DeviceTokenController::class, 'store']);
    Route::delete('device-tokens', [\App\Http\Controllers\Api\Devices\DeviceTokenController::class, 'destroy']);

    // FCM token alias — accepts both "token" and "fcm_token" fields (same handler)
    Route::post('fcm-token', [\App\Http\Controllers\Api\Devices\DeviceTokenController::class, 'store']);

    // Compatibility endpoint for creating gate visitor requests in E2E flows.
    Route::middleware('role:SECURITY')->post('visitor-requests', [VisitorRequestController::class, 'store']);
    Route::get('notifications', [NotificationController::class, 'index']);
    Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::match(['patch', 'post'], 'notifications/{notification}/read', [NotificationController::class, 'read']);
    Route::match(['patch', 'post'], 'notifications/read-all', [NotificationController::class, 'readAll']);
    Route::get('conversations', [MessagingController::class, 'index']);
    Route::post('conversations', [MessagingController::class, 'store']);
    Route::get('conversations/{conversation}', [MessagingController::class, 'show']);
    Route::post('conversations/{conversation}/messages', [MessagingController::class, 'send']);
    Route::patch('conversations/{conversation}/read', [MessagingController::class, 'markRead']);
    Route::get('amenities', [AmenityController::class, 'index']);
    Route::get('resident/profile', [ResidentController::class, 'profile']);
    Route::patch('resident/profile', [ResidentController::class, 'updateProfile']);
    Route::middleware('role:RESIDENT')->get('resident/dashboard', ResidentDashboardController::class);

    Route::middleware('role:SECURITY')->get('security/dashboard', SecurityDashboardController::class);
    Route::middleware('role:SECURITY')->prefix('security/visitors')->group(function (): void {
        Route::get('options', [SelectionOptionsController::class, 'security']);
        Route::get('/', [SecurityVisitorController::class, 'index']);
        Route::post('/', [SecurityVisitorController::class, 'store']);
        Route::get('{visitor}', [SecurityVisitorController::class, 'show']);
        Route::patch('{visitor}/entry', [SecurityVisitorController::class, 'recordEntry']);
        Route::patch('{visitor}/exit', [SecurityVisitorController::class, 'recordExit']);
    });

    Route::middleware('role:RESIDENT')->prefix('resident/visitors')->group(function (): void {
        Route::get('/', [ResidentVisitorController::class, 'index']);
        Route::get('pending', [ResidentVisitorController::class, 'pending']);
        Route::post('pre-approvals', [ResidentVisitorController::class, 'preApprove']);
        Route::get('{visitor}', [ResidentVisitorController::class, 'show']);
        Route::patch('{visitor}/approve', [ResidentVisitorController::class, 'approve']);
        Route::patch('{visitor}/reject', [ResidentVisitorController::class, 'reject']);
    });

    Route::middleware('role:RESIDENT')->prefix('resident')->group(function (): void {
        Route::get('maintenance-bills', [ResidentMaintenanceBillController::class, 'index']);
        Route::get('maintenance-bills/{bill}', [ResidentMaintenanceBillController::class, 'show']);
        Route::get('maintenance-payments', [ResidentMaintenancePaymentController::class, 'index']);
        Route::post('maintenance-payments', [ResidentMaintenancePaymentController::class, 'store']);
        Route::get('maintenance-payments/{payment}', [ResidentMaintenancePaymentController::class, 'show']);
        Route::get('payment-orders', [ResidentPaymentOrderController::class, 'index']);
        Route::get('payment-summary', [ResidentPaymentOrderController::class, 'summary']);
        Route::post('payment-orders/full', [ResidentPaymentOrderController::class, 'store']);
        Route::post('payments/create-order', [PaymentGatewayController::class, 'createOrder']);
        Route::post('payments/verify', [PaymentGatewayController::class, 'verify']);
        Route::get('payment-orders/{paymentOrder}', [ResidentPaymentOrderController::class, 'show']);
        Route::patch('payment-orders/{paymentOrder}/cancel', [ResidentPaymentOrderController::class, 'cancel']);
        Route::post('payment-orders/{paymentOrder}/checkout', [ResidentPaymentOrderController::class, 'checkout']);
        Route::post('payment-orders/{paymentOrder}/confirm-demo', [ResidentPaymentOrderController::class, 'confirmDemo']);
        Route::get('payment-orders/{paymentOrder}/receipt', [ResidentPaymentOrderController::class, 'receipt']);
        Route::get('maintenance-history', [ResidentMaintenanceController::class, 'history']);
        Route::get('payment-history', [ResidentMaintenanceController::class, 'payments']);
        Route::get('transaction-history', [ResidentTransactionHistoryController::class, 'index']);
        Route::get('transaction-summary', [ResidentTransactionHistoryController::class, 'summary']);
        Route::get('transaction-category-breakdown', [ResidentTransactionHistoryController::class, 'categoryBreakdown']);
        Route::get('complaints', [ComplaintController::class, 'index']);
        Route::post('complaints', [ComplaintController::class, 'store']);
        Route::get('complaints/{complaint}', [ComplaintController::class, 'show']);
        Route::match(['put', 'patch'], 'complaints/{complaint}', [ComplaintController::class, 'update']);
        Route::get('notices', [NoticeController::class, 'index']);
        Route::get('notices/{notice}', [NoticeController::class, 'show']);
        Route::get('parking-slots', [ParkingController::class, 'index']);
        Route::get('amenity-bookings', [AmenityController::class, 'bookings']);
        Route::post('amenity-bookings', [AmenityController::class, 'book']);
        Route::patch('amenity-bookings/{booking}/cancel', [AmenityController::class, 'cancel']);
    });

    Route::middleware('role:STAFF')->prefix('staff')->group(function (): void {
        Route::get('dashboard', StaffDashboardController::class);
        Route::get('options', [SelectionOptionsController::class, 'staff']);
        Route::get('complaints', [ComplaintController::class, 'index']);
        Route::get('complaints/{complaint}', [ComplaintController::class, 'show']);
        Route::match(['put', 'patch'], 'complaints/{complaint}', [ComplaintController::class, 'update']);
        Route::get('parcels', [ParcelController::class, 'index']);
        Route::post('parcels', [ParcelController::class, 'store']);
        Route::get('parcels/{parcel}', [ParcelController::class, 'show']);
        Route::patch('parcels/{parcel}/collect', [ParcelController::class, 'collect']);
        Route::get('notices', [NoticeController::class, 'index']);
        Route::get('notices/{notice}', [NoticeController::class, 'show']);
    });

    Route::middleware('role:ADMIN')->prefix('admin')->group(function (): void {
        Route::get('options', [SelectionOptionsController::class, 'admin']);
        Route::get('dashboard', AdminDashboardController::class);
        Route::get('reports', AdminReportController::class);
        Route::apiResource('residents', ResidentController::class);
        Route::apiResource('flats', FlatController::class);
        Route::get('visitors', [AdminVisitorController::class, 'index']);
        Route::get('visitors/{visitor}', [AdminVisitorController::class, 'show']);
        Route::apiResource('maintenance-bills', AdminMaintenanceBillController::class);
        Route::get('maintenance-collection', [AdminMaintenanceBillController::class, 'collection']);
        Route::post('maintenance-generate', [AdminMaintenanceBillController::class, 'generate']);
        Route::get('maintenance-payments', [AdminMaintenancePaymentController::class, 'index']);
        Route::post('maintenance-payments', [AdminMaintenancePaymentController::class, 'store']);
        Route::get('maintenance-payments/{payment}', [AdminMaintenancePaymentController::class, 'show']);
        Route::patch('maintenance-payments/{payment}/status', [AdminMaintenancePaymentController::class, 'transition']);
        Route::get('payment-orders', [AdminPaymentOrderController::class, 'index']);
        Route::get('payment-orders/{paymentOrder}', [AdminPaymentOrderController::class, 'show']);
        Route::get('payment-orders/{paymentOrder}/receipt', [AdminPaymentOrderController::class, 'receipt']);
        Route::patch('payment-orders/{paymentOrder}/status', [AdminPaymentOrderController::class, 'transition']);
        Route::get('complaints', [ComplaintController::class, 'index']);
        Route::get('complaints/{complaint}', [ComplaintController::class, 'show']);
        Route::match(['put', 'patch'], 'complaints/{complaint}', [ComplaintController::class, 'update']);
        Route::apiResource('notices', NoticeController::class)->except('destroy');
        Route::patch('staff-members/{staffMember}/status', [AdminStaffMemberController::class, 'updateStatus']);
        Route::apiResource('staff-members', AdminStaffMemberController::class)->except('destroy');
        Route::apiResource('parking-slots', ParkingController::class)->except('destroy');
        Route::apiResource('amenities', AmenityController::class)->except(['show', 'destroy']);
        Route::get('amenity-bookings', [AmenityController::class, 'bookings']);
        Route::patch('amenity-bookings/{booking}/cancel', [AmenityController::class, 'cancel']);
        Route::patch('amenity-bookings/{booking}/status', [AmenityController::class, 'updateStatus']);
        Route::get('parcels', [ParcelController::class, 'index']);
        Route::post('parcels', [ParcelController::class, 'store']);
        Route::get('parcels/{parcel}', [ParcelController::class, 'show']);
        Route::patch('parcels/{parcel}/collect', [ParcelController::class, 'collect']);
    });

    Route::middleware('role:RESIDENT')->prefix('resident')->group(function (): void {
        Route::get('parcels', [ParcelController::class, 'index']);
        Route::get('parcels/{parcel}', [ParcelController::class, 'show']);
    });

    Route::middleware('role:SECURITY')->prefix('security')->group(function (): void {
        Route::get('parcels', [ParcelController::class, 'index']);
        Route::post('parcels', [ParcelController::class, 'store']);
        Route::get('parcels/{parcel}', [ParcelController::class, 'show']);
        Route::patch('parcels/{parcel}/collect', [ParcelController::class, 'collect']);
        Route::get('notices', [NoticeController::class, 'index']);
        Route::get('notices/{notice}', [NoticeController::class, 'show']);
    });
});

Route::post('webhooks/razorpay', [PaymentGatewayController::class, 'webhook']);

