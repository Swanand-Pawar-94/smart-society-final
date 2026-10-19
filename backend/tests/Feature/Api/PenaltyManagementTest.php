<?php

namespace Tests\Feature\Api;

use App\Models\Flat;
use App\Models\MaintenanceBill;
use App\Models\Penalty;
use App\Models\PenaltyRule;
use App\Models\Resident;
use App\Models\User;
use App\Models\ViolationReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PenaltyManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_security_can_report_but_cannot_decide_or_configure_rules(): void
    {
        $security = User::create(['name' => 'Gate', 'email' => 'gate@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $flat = Flat::create(['flat_number' => '101', 'building' => 'A', 'occupancy_status' => 'OCCUPIED']);
        Resident::create(['user_id' => User::create(['name' => 'Owner', 'email' => 'owner@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT])->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        PenaltyRule::create(['category' => 'parking_vehicle', 'violation_type' => 'fire_lane', 'minimum_amount' => 100, 'maximum_amount' => 500, 'requires_evidence' => false]);
        Sanctum::actingAs($security);

        $payload = ['category' => 'parking_vehicle', 'violation_type' => 'fire_lane', 'flat_id' => $flat->id, 'incident_at' => now()->subMinute()->toISOString(), 'location' => 'Basement', 'description' => 'Car parked in fire lane'];
        $this->postJson('/api/penalty-reports', $payload)->assertCreated()->assertJsonPath('data.status', 'reported');
        $this->postJson('/api/penalty-reports', $payload)->assertUnprocessable();
        $report = ViolationReport::firstOrFail();
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'reason' => 'Fine'])->assertForbidden();
        $this->postJson('/api/admin/penalty-rules', [])->assertForbidden();
    }

    public function test_type_must_match_category_and_residents_only_see_own_flat(): void
    {
        $security = User::create(['name' => 'Gate', 'email' => 'gate2@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        Sanctum::actingAs($security);
        $this->postJson('/api/penalty-reports', ['category' => 'noise_nuisance', 'violation_type' => 'fire_lane', 'incident_at' => now()->subMinute()->toISOString(), 'location' => 'Road', 'description' => 'Misclassified report'])->assertUnprocessable();

        $flat = Flat::create(['flat_number' => '202', 'building' => 'B', 'occupancy_status' => 'OCCUPIED']);
        $resident = User::create(['name' => 'Resident', 'email' => 'resident2@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        Resident::create(['user_id' => $resident->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        ViolationReport::create(['category' => 'property_safety', 'violation_type' => 'blocked_emergency_exit', 'flat_id' => $flat->id, 'resident_id' => Resident::where('user_id', $resident->id)->value('id'), 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Exit', 'description' => 'Blocked', 'status' => 'reported']);
        Sanctum::actingAs($resident);
        $this->getJson('/api/penalty-reports')->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_admin_approval_requires_an_active_configured_rule_and_preserves_reason(): void
    {
        $admin = User::create(['name' => 'Admin', 'email' => 'admin-penalty@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $security = User::create(['name' => 'Gate', 'email' => 'gate3@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $flat = Flat::create(['flat_number' => '303', 'building' => 'C', 'occupancy_status' => 'OCCUPIED']);
        $resident = User::create(['name' => 'Resident', 'email' => 'resident3@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $residentRow = Resident::create(['user_id' => $resident->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        $report = ViolationReport::create(['category' => 'parking_vehicle', 'violation_type' => 'fire_lane', 'flat_id' => $flat->id, 'resident_id' => $residentRow->id, 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Entry', 'description' => 'Unsafe parking', 'status' => 'reported']);
        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 100, 'reason' => 'Authorized fine'])->assertUnprocessable();
        PenaltyRule::create(['category' => 'parking_vehicle', 'violation_type' => 'fire_lane', 'minimum_amount' => 50, 'maximum_amount' => 150, 'requires_evidence' => false]);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 100, 'reason' => 'Authorized fine'])->assertOk()->assertJsonPath('data.penalty.disciplinary_amount', '100.00');
        $this->assertDatabaseHas('penalty_audit_logs', ['violation_report_id' => $report->id, 'action' => 'approved', 'reason' => 'Authorized fine']);
    }

    public function test_penalty_payment_uses_existing_gateway_verification_and_is_idempotent(): void
    {
        config(['services.razorpay.key_id' => 'rzp_test_configured', 'services.razorpay.key_secret' => 'test_secret']);
        Http::fake(['https://api.razorpay.com/v1/orders' => Http::response(['id' => 'order_penalty_1'], 200)]);
        $user = User::create(['name' => 'Payer', 'email' => 'payer@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $flat = Flat::create(['flat_number' => '404', 'building' => 'D', 'occupancy_status' => 'OCCUPIED']);
        $resident = Resident::create(['user_id' => $user->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        $admin = User::create(['name' => 'Admin', 'email' => 'admin-paypenalty@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $report = ViolationReport::create(['category' => 'property_safety', 'violation_type' => 'property_damage', 'flat_id' => $flat->id, 'resident_id' => $resident->id, 'reported_by_user_id' => $admin->id, 'incident_at' => now(), 'location' => 'Lobby', 'description' => 'Documented damage', 'status' => 'approved']);
        $penalty = Penalty::create(['violation_report_id' => $report->id, 'resident_id' => $resident->id, 'flat_id' => $flat->id, 'disciplinary_amount' => 200, 'repair_cost' => 35, 'status' => 'approved', 'payment_status' => 'unpaid', 'decision_reason' => 'Approved cost', 'decided_by_user_id' => $admin->id, 'decided_at' => now()]);
        Sanctum::actingAs($user);
        $checkout = $this->postJson("/api/resident/penalties/{$penalty->id}/payment", [])->assertCreated()->assertJsonPath('data.order_id', 'order_penalty_1');
        $orderId = $checkout->json('data.order_id');
        $paymentId = 'pay_penalty_1';
        $signature = hash_hmac('sha256', $orderId.'|'.$paymentId, 'test_secret');
        $payload = ['razorpay_order_id' => $orderId, 'razorpay_payment_id' => $paymentId, 'razorpay_signature' => $signature];
        $this->postJson('/api/resident/payments/verify', $payload)->assertOk()->assertJsonPath('data.success', true);
        $this->postJson('/api/resident/payments/verify', $payload)->assertOk()->assertJsonPath('data.success', true);
        $this->assertDatabaseHas('penalties', ['id' => $penalty->id, 'payment_status' => 'paid']);
        $this->assertDatabaseCount('payment_order_items', 1);
        $this->assertDatabaseHas('payment_order_items', ['penalty_id' => $penalty->id, 'maintenance_bill_id' => null]);
    }

    public function test_late_maintenance_fee_uses_configured_fee_and_keeps_principal_separate(): void
    {
        $admin = User::create(['name' => 'Admin', 'email' => 'admin-late@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $security = User::create(['name' => 'Gate', 'email' => 'gate-late@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $residentUser = User::create(['name' => 'Resident', 'email' => 'resident-late@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $flat = Flat::create(['flat_number' => '505', 'building' => 'E', 'occupancy_status' => 'OCCUPIED']);
        $resident = Resident::create(['user_id' => $residentUser->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        $bill = MaintenanceBill::create(['flat_id' => $flat->id, 'billing_month' => today()->subMonth()->startOfMonth(), 'due_date' => today()->subDays(10), 'amount' => 300, 'status' => MaintenanceBill::STATUS_UNPAID]);
        PenaltyRule::create(['category' => 'maintenance_financial', 'violation_type' => 'late_maintenance', 'minimum_amount' => 50, 'maximum_amount' => 50, 'late_fee_amount' => 50, 'grace_period_days' => 5, 'requires_evidence' => false]);
        $report = ViolationReport::create(['category' => 'maintenance_financial', 'violation_type' => 'late_maintenance', 'flat_id' => $flat->id, 'resident_id' => $resident->id, 'maintenance_bill_id' => $bill->id, 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Accounts', 'description' => 'Late maintenance payment', 'status' => 'reported']);
        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'reason' => 'Configured late fee'])->assertOk()->assertJsonPath('data.penalty.disciplinary_amount', '0.00')->assertJsonPath('data.penalty.late_fee_amount', '50.00');
        $this->assertDatabaseHas('maintenance_bills', ['id' => $bill->id, 'amount' => 300]);

        $duplicate = ViolationReport::create(['category' => 'maintenance_financial', 'violation_type' => 'late_maintenance', 'flat_id' => $flat->id, 'resident_id' => $resident->id, 'maintenance_bill_id' => $bill->id, 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Accounts', 'description' => 'Duplicate late fee report', 'status' => 'reported']);
        $this->postJson("/api/admin/penalty-reports/{$duplicate->id}/decision", ['decision' => 'approved', 'reason' => 'Duplicate'])->assertUnprocessable();
    }

    public function test_evidence_is_private_and_only_visible_to_authorized_report_parties(): void
    {
        Storage::fake('local');
        $security = User::create(['name' => 'Gate', 'email' => 'gate-evidence@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $flat = Flat::create(['flat_number' => '606', 'building' => 'F', 'occupancy_status' => 'OCCUPIED']);
        $resident = User::create(['name' => 'Owner', 'email' => 'owner-evidence@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        Resident::create(['user_id' => $resident->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        Sanctum::actingAs($security);
        $response = $this->withHeaders(['Accept' => 'application/json'])->post('/api/penalty-reports', ['category' => 'property_safety', 'violation_type' => 'property_damage', 'flat_id' => $flat->id, 'incident_at' => now()->subMinute()->toISOString(), 'location' => 'Lobby', 'description' => 'Broken fixture', 'evidence' => [UploadedFile::fake()->create('fixture.pdf', 100, 'application/pdf')]])->assertCreated();
        $evidenceId = $response->json('data.evidence.0.id');
        $this->get('/api/penalty-evidence/'.$evidenceId)->assertOk();
        $otherSecurity = User::create(['name' => 'Other gate', 'email' => 'gate-other-evidence@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        Sanctum::actingAs($otherSecurity);
        $this->getJson('/api/penalty-evidence/'.$evidenceId)->assertNotFound();
        Sanctum::actingAs($resident);
        $this->get('/api/penalty-evidence/'.$evidenceId)->assertOk();
    }

    public function test_resident_appeal_evidence_and_admin_waiver_are_audited(): void
    {
        Storage::fake('local');
        $residentUser = User::create(['name' => 'Appealing resident', 'email' => 'appeal-resident@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $admin = User::create(['name' => 'Admin', 'email' => 'appeal-admin@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $reporter = User::create(['name' => 'Gate', 'email' => 'appeal-gate@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $flat = Flat::create(['flat_number' => '707', 'building' => 'G', 'occupancy_status' => 'OCCUPIED']);
        $resident = Resident::create(['user_id' => $residentUser->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        $report = ViolationReport::create(['category' => 'parking_vehicle', 'violation_type' => 'no_parking', 'flat_id' => $flat->id, 'resident_id' => $resident->id, 'reported_by_user_id' => $reporter->id, 'incident_at' => now(), 'location' => 'Ramp', 'description' => 'Vehicle parked in restricted area', 'status' => 'approved']);
        $penalty = Penalty::create(['violation_report_id' => $report->id, 'resident_id' => $resident->id, 'flat_id' => $flat->id, 'disciplinary_amount' => 125, 'status' => 'approved', 'payment_status' => 'unpaid', 'decision_reason' => 'Configured penalty', 'decided_by_user_id' => $admin->id, 'decided_at' => now()]);
        Sanctum::actingAs($residentUser);
        $response = $this->withHeaders(['Accept' => 'application/json'])->post("/api/resident/penalties/{$penalty->id}/appeals", ['reason' => 'I was not parked in the ramp.', 'evidence' => [UploadedFile::fake()->create('receipt.pdf', 50, 'application/pdf')]])->assertCreated();
        $appealId = $response->json('data.id');
        $this->assertDatabaseHas('violation_evidence', ['violation_report_id' => $report->id, 'appeal_id' => $appealId]);

        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-appeals/{$appealId}/decision", ['decision' => 'waived', 'reason' => 'Evidence supports the appeal.'])->assertOk()->assertJsonPath('data.status', 'waived');
        $this->assertDatabaseHas('penalties', ['id' => $penalty->id, 'status' => 'waived', 'payment_status' => 'waived']);
        $this->assertDatabaseHas('penalty_audit_logs', ['violation_report_id' => $report->id, 'action' => 'appeal_waived', 'reason' => 'Evidence supports the appeal.']);
    }
}
