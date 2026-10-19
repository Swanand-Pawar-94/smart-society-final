<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('penalty_rules', function (Blueprint $table): void {
            $table->id();
            $table->string('category', 40)->index();
            $table->string('violation_type', 100);
            $table->text('description')->nullable();
            $table->decimal('minimum_amount', 12, 2)->default(0);
            $table->decimal('maximum_amount', 12, 2)->nullable();
            $table->decimal('late_fee_amount', 12, 2)->nullable();
            $table->unsignedSmallInteger('grace_period_days')->default(0);
            $table->boolean('requires_evidence')->default(true);
            $table->boolean('active')->default(true)->index();
            $table->foreignId('updated_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            $table->unique(['category', 'violation_type']);
        });

        Schema::create('violation_reports', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('rule_id')->nullable()->constrained('penalty_rules')->nullOnDelete();
            $table->string('category', 40)->index();
            $table->string('violation_type', 100);
            $table->foreignId('flat_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('resident_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('vehicle_slot_id')->nullable()->constrained('parking_slots')->nullOnDelete();
            $table->foreignId('maintenance_bill_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('booking_id')->nullable()->constrained('amenity_bookings')->nullOnDelete();
            $table->foreignId('reported_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->dateTime('incident_at');
            $table->string('incident_fingerprint', 64)->nullable()->unique();
            $table->string('location', 255);
            $table->text('description');
            $table->string('status', 30)->default('reported')->index();
            $table->timestamps();
            $table->index(['flat_id', 'status', 'created_at']);
        });

        Schema::create('violation_evidence', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('violation_report_id')->constrained()->cascadeOnDelete();
            $table->foreignId('appeal_id')->nullable();
            $table->foreignId('uploaded_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('disk', 50)->default('local');
            $table->string('path', 500);
            $table->string('original_name', 255);
            $table->string('mime_type', 100);
            $table->unsignedBigInteger('size_bytes');
            $table->timestamps();
            $table->index(['violation_report_id', 'created_at']);
        });

        Schema::create('penalties', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('violation_report_id')->unique()->constrained()->cascadeOnDelete();
            $table->foreignId('resident_id')->constrained()->cascadeOnDelete();
            $table->foreignId('flat_id')->constrained()->cascadeOnDelete();
            $table->decimal('disciplinary_amount', 12, 2)->default(0);
            $table->decimal('repair_cost', 12, 2)->default(0);
            $table->decimal('late_fee_amount', 12, 2)->default(0);
            $table->foreignId('maintenance_bill_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('booking_id')->nullable()->constrained('amenity_bookings')->nullOnDelete();
            $table->string('late_fee_period', 7)->nullable();
            $table->string('status', 30)->default('pending')->index();
            $table->string('payment_status', 30)->default('unpaid')->index();
            $table->date('due_date')->nullable();
            $table->text('decision_reason');
            $table->foreignId('decided_by_user_id')->constrained('users')->cascadeOnDelete();
            $table->timestamp('decided_at');
            $table->timestamps();
            $table->index(['resident_id', 'status']);
            $table->unique(['maintenance_bill_id', 'late_fee_period']);
        });

        Schema::create('penalty_appeals', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('penalty_id')->constrained()->cascadeOnDelete();
            $table->foreignId('resident_id')->constrained()->cascadeOnDelete();
            $table->text('reason');
            $table->string('status', 30)->default('submitted')->index();
            $table->text('decision_reason')->nullable();
            $table->foreignId('decided_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('decided_at')->nullable();
            $table->timestamps();
            $table->index(['penalty_id', 'status']);
        });

        Schema::create('penalty_audit_logs', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('violation_report_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('action', 50);
            $table->string('from_status', 30)->nullable();
            $table->string('to_status', 30)->nullable();
            $table->text('reason')->nullable();
            $table->json('details')->nullable();
            $table->timestamps();
            $table->index(['violation_report_id', 'created_at']);
        });

        Schema::table('payment_order_items', function (Blueprint $table): void {
            $table->foreignId('maintenance_bill_id')->nullable()->change();
            $table->foreignId('penalty_id')->nullable()->after('maintenance_bill_id')->constrained('penalties')->nullOnDelete();
            $table->unique(['payment_order_id', 'penalty_id']);
        });
    }

    public function down(): void
    {
        Schema::table('payment_order_items', function (Blueprint $table): void {
            $table->dropUnique(['payment_order_id', 'penalty_id']);
            $table->dropConstrainedForeignId('penalty_id');
        });
        Schema::dropIfExists('penalty_audit_logs');
        Schema::dropIfExists('penalty_appeals');
        Schema::dropIfExists('penalties');
        Schema::dropIfExists('violation_evidence');
        Schema::dropIfExists('violation_reports');
        Schema::dropIfExists('penalty_rules');
    }
};
