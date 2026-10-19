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
        $this->postJson('/api/penalty-reports', $payload)->assertCreated()->assertJsonPath('data.status', 'reported')->assertJsonPath('data.resident_id', null);
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
        $otherResident = User::create(['name' => 'Flatmate', 'email' => 'flatmate2@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $otherResidentRow = Resident::create(['user_id' => $otherResident->id, 'flat_id' => $flat->id]);
        ViolationReport::create(['category' => 'property_safety', 'violation_type' => 'blocked_emergency_exit', 'flat_id' => $flat->id, 'resident_id' => Resident::where('user_id', $resident->id)->value('id'), 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Exit', 'description' => 'Blocked', 'status' => 'reported']);
        ViolationReport::create(['category' => 'property_safety', 'violation_type' => 'property_damage', 'flat_id' => $flat->id, 'resident_id' => $otherResidentRow->id, 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Hallway', 'description' => 'Damage', 'status' => 'reported']);
        Sanctum::actingAs($resident);
        $this->getJson('/api/penalty-reports')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.violation_type', 'blocked_emergency_exit');
        $this->getJson('/api/penalty-reports/'.ViolationReport::where('resident_id', $otherResidentRow->id)->value('id'))->assertNotFound();
    }

    public function test_admin_can_approve_without_rule_assigns_verified_resident_and_prevents_duplicates(): void
    {
        $admin = User::create(['name' => 'Admin', 'email' => 'admin-penalty@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $security = User::create(['name' => 'Gate', 'email' => 'gate3@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $flat = Flat::create(['flat_number' => '303', 'building' => 'C', 'occupancy_status' => 'OCCUPIED']);
        $resident = User::create(['name' => 'Resident', 'email' => 'resident3@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $residentRow = Resident::create(['user_id' => $resident->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        $report = ViolationReport::create(['category' => 'parking_vehicle', 'violation_type' => 'fire_lane', 'flat_id' => $flat->id, 'resident_id' => $residentRow->id, 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Entry', 'description' => 'Unsafe parking', 'status' => 'reported']);
        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 100, 'responsible_resident_id' => $residentRow->id, 'reason' => 'Authorized fine'])->assertOk()->assertJsonPath('data.penalty.disciplinary_amount', '100.00');
        $this->assertDatabaseHas('penalties', ['violation_report_id' => $report->id, 'resident_id' => $residentRow->id, 'flat_id' => $flat->id, 'payment_status' => 'unpaid']);
        $this->assertDatabaseHas('violation_reports', ['id' => $report->id, 'status' => 'approved', 'resident_id' => $residentRow->id]);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 100, 'responsible_resident_id' => $residentRow->id, 'reason' => 'Duplicate'])->assertUnprocessable();
        $this->assertDatabaseHas('penalty_audit_logs', ['violation_report_id' => $report->id, 'action' => 'approved', 'reason' => 'Authorized fine']);
    }

    public function test_admin_cannot_assign_a_resident_from_another_flat_and_can_leave_report_under_investigation(): void
    {
        $admin = User::create(['name' => 'Admin', 'email' => 'admin-investigate@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $reporter = User::create(['name' => 'Gate', 'email' => 'gate-investigate@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $flat = Flat::create(['flat_number' => '707', 'building' => 'G', 'occupancy_status' => 'OCCUPIED']);
        $otherFlat = Flat::create(['flat_number' => '708', 'building' => 'G', 'occupancy_status' => 'OCCUPIED']);
        $resident = Resident::create(['user_id' => User::create(['name' => 'Other resident', 'email' => 'other-investigate@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT])->id, 'flat_id' => $otherFlat->id]);
        $report = ViolationReport::create(['category' => 'parking_vehicle', 'violation_type' => 'fire_lane', 'flat_id' => $flat->id, 'reported_by_user_id' => $reporter->id, 'incident_at' => now(), 'location' => 'Entry', 'description' => 'Unidentified vehicle', 'status' => 'reported']);
        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 25, 'responsible_resident_id' => $resident->id, 'reason' => 'Cannot link other flat'])->assertUnprocessable();
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'under_review', 'reason' => 'Responsible person not yet identified'])->assertOk()->assertJsonPath('data.status', 'under_review');
        $this->assertDatabaseMissing('penalties', ['violation_report_id' => $report->id]);
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

    public function test_late_maintenance_violation_uses_administrator_amount_without_a_rule(): void
    {
        $admin = User::create(['name' => 'Admin', 'email' => 'admin-late@example.test', 'password' => 'Password123!', 'role' => User::ROLE_ADMIN]);
        $security = User::create(['name' => 'Gate', 'email' => 'gate-late@example.test', 'password' => 'Password123!', 'role' => User::ROLE_SECURITY]);
        $residentUser = User::create(['name' => 'Resident', 'email' => 'resident-late@example.test', 'password' => 'Password123!', 'role' => User::ROLE_RESIDENT]);
        $flat = Flat::create(['flat_number' => '505', 'building' => 'E', 'occupancy_status' => 'OCCUPIED']);
        $resident = Resident::create(['user_id' => $residentUser->id, 'flat_id' => $flat->id, 'is_primary_contact' => true]);
        $bill = MaintenanceBill::create(['flat_id' => $flat->id, 'billing_month' => today()->subMonth()->startOfMonth(), 'due_date' => today()->subDays(10), 'amount' => 300, 'status' => MaintenanceBill::STATUS_UNPAID]);
        $report = ViolationReport::create(['category' => 'maintenance_financial', 'violation_type' => 'late_maintenance', 'flat_id' => $flat->id, 'resident_id' => $resident->id, 'maintenance_bill_id' => $bill->id, 'reported_by_user_id' => $security->id, 'incident_at' => now(), 'location' => 'Accounts', 'description' => 'Late maintenance payment', 'status' => 'reported']);
        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 75, 'responsible_resident_id' => $resident->id, 'reason' => 'Administrator assessed amount'])->assertOk()->assertJsonPath('data.penalty.disciplinary_amount', '75.00')->assertJsonPath('data.penalty.late_fee_amount', '0.00');
        $this->assertDatabaseHas('maintenance_bills', ['id' => $bill->id, 'amount' => 300]);
        $this->postJson("/api/admin/penalty-reports/{$report->id}/decision", ['decision' => 'approved', 'disciplinary_amount' => 75, 'responsible_resident_id' => $resident->id, 'reason' => 'Duplicate'])->assertUnprocessable();
    }

    public function test_evidence_is_private_and_unassigned_residents_cannot_view_it(): void
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
        $this->get('/api/penalty-evidence/'.$evidenceId)->assertNotFound();
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
        $this->getJson('/api/penalty-reports')->assertOk()->assertJsonPath('data.0.penalty.appeals.0.status', 'submitted');

        Sanctum::actingAs($admin);
        $this->postJson("/api/admin/penalty-appeals/{$appealId}/decision", ['decision' => 'waived', 'reason' => 'Evidence supports the appeal.'])->assertOk()->assertJsonPath('data.status', 'waived');
        $this->assertDatabaseHas('penalties', ['id' => $penalty->id, 'status' => 'waived', 'payment_status' => 'waived']);
        $this->assertDatabaseHas('penalty_audit_logs', ['violation_report_id' => $report->id, 'action' => 'appeal_waived', 'reason' => 'Evidence supports the appeal.']);
    }
}
