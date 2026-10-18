<?php

namespace Tests\Feature\Api;

use App\Models\Flat;
use App\Models\MaintenanceBill;
use App\Models\MaintenancePayment;
use App\Models\PaymentOrder;
use App\Models\Resident;
use App\Models\User;
use App\Services\Payment\RazorpayGatewayService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RazorpayPaymentTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Keep the suite deterministic and never use developer or production
        // Razorpay credentials from the host environment.
        config([
            'services.razorpay.key_id' => 'rzp_test_dummy',
            'services.razorpay.key_secret' => 'dummy_razorpay_secret_key',
        ]);
    }

    private function resident(string $flatNumber, string $email): Resident
    {
        $user = User::factory()->create([
            'email' => $email,
            'role' => User::ROLE_RESIDENT,
        ]);

        $flat = Flat::create([
            'flat_number' => $flatNumber,
            'building' => 'A',
            'floor' => '1',
            'occupancy_status' => 'OCCUPIED',
        ]);

        return Resident::create([
            'user_id' => $user->id,
            'flat_id' => $flat->id,
            'relation_to_owner' => 'OWNER',
            'is_primary_contact' => true,
        ]);
    }

    public function test_single_invoice_payment_order_creates_order_for_only_selected_invoice(): void
    {
        $resident = $this->resident('101', 'resident1@test.local');

        $augustBill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'billing_period_start' => Carbon::parse('2026-08-01'),
            'billing_period_end' => Carbon::parse('2026-08-31'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        $septemberBill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-09-01'),
            'billing_period_start' => Carbon::parse('2026-09-01'),
            'billing_period_end' => Carbon::parse('2026-09-30'),
            'due_date' => Carbon::parse('2026-09-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        Sanctum::actingAs($resident->user);

        // Request single-invoice Razorpay order for August
        $response = $this->postJson('/api/resident/payments/create-order', [
            'invoiceId' => $augustBill->id,
        ]);

        $response->assertOk()
            ->assertJsonPath('data.amount', 200000) // 2000.00 INR in paise
            ->assertJsonPath('data.amount_formatted', 2000)
            ->assertJsonPath('data.currency', 'INR')
            ->assertJsonPath('data.maintenance_bill_id', $augustBill->id)
            ->assertJsonPath('data.is_single_invoice', true);

        $orderId = $response->json('data.order_id');
        $this->assertNotEmpty($orderId);

        // Verify that only 1 PaymentOrder was created for 2000.00
        $this->assertDatabaseHas('payment_orders', [
            'resident_id' => $resident->id,
            'flat_id' => $resident->flat_id,
            'amount' => 2000,
            'provider' => 'RAZORPAY',
            'provider_reference' => $orderId,
            'status' => PaymentOrder::STATUS_PENDING,
        ]);
    }

    public function test_pay_all_outstanding_dues_creates_order_for_total(): void
    {
        $resident = $this->resident('102', 'resident2@test.local');

        $augustBill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        $septemberBill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-09-01'),
            'due_date' => Carbon::parse('2026-09-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        Sanctum::actingAs($resident->user);

        // Request pay-all order
        $response = $this->postJson('/api/resident/payments/create-order', [
            'pay_all' => true,
        ]);

        $response->assertOk()
            ->assertJsonPath('data.amount', 400000) // 4000.00 INR in paise
            ->assertJsonPath('data.amount_formatted', 4000)
            ->assertJsonPath('data.is_single_invoice', false);
    }

    public function test_successful_signature_verification_settles_only_selected_invoice(): void
    {
        $resident = $this->resident('103', 'resident3@test.local');

        $augustBill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        $septemberBill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-09-01'),
            'due_date' => Carbon::parse('2026-09-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        Sanctum::actingAs($resident->user);

        // Create order for August
        $orderRes = $this->postJson('/api/resident/payments/create-order', [
            'invoiceId' => $augustBill->id,
        ])->assertOk();

        $orderId = $orderRes->json('data.order_id');
        $paymentId = 'pay_test_' . rand(100000, 999999);

        $gateway = app(RazorpayGatewayService::class);
        $validSignature = $gateway->generateTestSignature($orderId, $paymentId);

        // Verify payment
        $verifyRes = $this->postJson('/api/resident/payments/verify', [
            'razorpay_order_id' => $orderId,
            'razorpay_payment_id' => $paymentId,
            'razorpay_signature' => $validSignature,
        ]);

        $verifyRes->assertOk()
            ->assertJsonPath('data.success', true)
            ->assertJsonPath('data.payment_id', $paymentId);

        // CRITICAL CHECK: August is PAID, September remains UNPAID
        $this->assertEquals(MaintenanceBill::STATUS_PAID, $augustBill->fresh()->status);
        $this->assertEquals(MaintenanceBill::STATUS_UNPAID, $septemberBill->fresh()->status);

        // Check PaymentOrder status is SUCCESSFUL
        $order = PaymentOrder::where('provider_reference', $orderId)->first();
        $this->assertEquals(PaymentOrder::STATUS_SUCCESSFUL, $order->status);
        $this->assertEquals($paymentId, $order->gateway_payment_id);

        // Check MaintenancePayment record
        $this->assertDatabaseHas('maintenance_payments', [
            'maintenance_bill_id' => $augustBill->id,
            'resident_id' => $resident->id,
            'amount' => 2000,
            'status' => MaintenancePayment::STATUS_COMPLETED,
        ]);
    }

    public function test_invalid_signature_is_rejected_and_leaves_invoice_unpaid(): void
    {
        $resident = $this->resident('104', 'resident4@test.local');

        $bill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        Sanctum::actingAs($resident->user);

        $orderRes = $this->postJson('/api/resident/payments/create-order', [
            'invoiceId' => $bill->id,
        ])->assertOk();

        $orderId = $orderRes->json('data.order_id');

        // Submit invalid signature
        $verifyRes = $this->postJson('/api/resident/payments/verify', [
            'razorpay_order_id' => $orderId,
            'razorpay_payment_id' => 'pay_fake_123456',
            'razorpay_signature' => 'invalid_signature_hex_value',
        ]);

        $verifyRes->assertStatus(422);

        // Bill MUST remain UNPAID
        $this->assertEquals(MaintenanceBill::STATUS_UNPAID, $bill->fresh()->status);
    }

    public function test_attempting_to_create_order_for_already_paid_invoice_is_rejected(): void
    {
        $resident = $this->resident('105', 'resident5@test.local');

        $bill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_PAID,
        ]);

        // Add completed payment for the bill
        MaintenancePayment::create([
            'maintenance_bill_id' => $bill->id,
            'resident_id' => $resident->id,
            'amount' => 2000,
            'payment_method' => 'UPI',
            'status' => MaintenancePayment::STATUS_COMPLETED,
            'paid_at' => now(),
        ]);

        Sanctum::actingAs($resident->user);

        $this->postJson('/api/resident/payments/create-order', [
            'invoiceId' => $bill->id,
        ])->assertStatus(422);
    }

    public function test_resident_cannot_pay_another_residents_invoice(): void
    {
        $resident1 = $this->resident('106', 'resident6@test.local');
        $resident2 = $this->resident('107', 'resident7@test.local');

        $foreignBill = MaintenanceBill::create([
            'flat_id' => $resident2->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        Sanctum::actingAs($resident1->user);

        $this->postJson('/api/resident/payments/create-order', [
            'invoiceId' => $foreignBill->id,
        ])->assertStatus(422);
    }

    public function test_payment_verification_is_idempotent(): void
    {
        $resident = $this->resident('108', 'resident8@test.local');

        $bill = MaintenanceBill::create([
            'flat_id' => $resident->flat_id,
            'billing_month' => Carbon::parse('2026-08-01'),
            'due_date' => Carbon::parse('2026-08-16'),
            'amount' => 2000,
            'status' => MaintenanceBill::STATUS_UNPAID,
        ]);

        Sanctum::actingAs($resident->user);

        $orderRes = $this->postJson('/api/resident/payments/create-order', [
            'invoiceId' => $bill->id,
        ])->assertOk();

        $orderId = $orderRes->json('data.order_id');
        $paymentId = 'pay_test_' . rand(100000, 999999);

        $gateway = app(RazorpayGatewayService::class);
        $signature = $gateway->generateTestSignature($orderId, $paymentId);

        // First verification
        $this->postJson('/api/resident/payments/verify', [
            'razorpay_order_id' => $orderId,
            'razorpay_payment_id' => $paymentId,
            'razorpay_signature' => $signature,
        ])->assertOk();

        $this->assertEquals(1, MaintenancePayment::where('maintenance_bill_id', $bill->id)->count());

        // Second verification (same payload)
        $secondRes = $this->postJson('/api/resident/payments/verify', [
            'razorpay_order_id' => $orderId,
            'razorpay_payment_id' => $paymentId,
            'razorpay_signature' => $signature,
        ]);

        $secondRes->assertOk();
        // Payments count must STILL be exactly 1
        $this->assertEquals(1, MaintenancePayment::where('maintenance_bill_id', $bill->id)->count());
    }
}
