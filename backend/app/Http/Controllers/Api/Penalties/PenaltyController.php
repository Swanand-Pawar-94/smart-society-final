<?php

namespace App\Http\Controllers\Api\Penalties;

use App\Exceptions\PaymentGatewayUnavailableException;
use App\Http\Controllers\Controller;
use App\Models\AmenityBooking;
use App\Models\MaintenanceBill;
use App\Models\ParkingSlot;
use App\Models\Penalty;
use App\Models\PenaltyAppeal;
use App\Models\PenaltyAuditLog;
use App\Models\PenaltyRule;
use App\Models\Resident;
use App\Models\User;
use App\Models\ViolationEvidence;
use App\Models\ViolationReport;
use App\Notifications\SocietyAlert;
use App\Services\Maintenance\PaymentOrderService;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class PenaltyController extends Controller
{
    private const CATEGORIES = [
        'parking_vehicle' => ['assigned_slot', 'blocking_vehicle', 'fire_lane', 'no_parking', 'visitor_parking', 'unregistered_vehicle'],
        'noise_nuisance' => ['quiet_hours', 'party_noise', 'common_area_disturbance', 'unauthorized_loudspeaker', 'out_of_hours_construction'],
        'maintenance_financial' => ['late_maintenance', 'late_booking', 'unpaid_authorized_charge', 'breached_payment_schedule'],
        'property_safety' => ['property_damage', 'safety_equipment_tampering', 'blocked_emergency_exit', 'unauthorized_modification', 'shared_property_damage', 'restricted_room_access'],
    ];

    public function rules(Request $request)
    {
        return response()->json(['data' => PenaltyRule::query()->where('active', true)->orderBy('category')->orderBy('violation_type')->get()]);
    }

    public function reports(Request $request)
    {
        $user = $request->user();
        $query = ViolationReport::query()->with(['rule', 'flat:id,flat_number,building', 'reporter:id,name', 'penalty.appeals', 'evidence:id,violation_report_id,original_name,mime_type,size_bytes']);
        if ($user->hasRole('ADMIN')) {
            $query->with('flat.residents:id,user_id,flat_id');
            $query->with('flat.residents.user:id,name');
        }
        if ($user->hasRole('RESIDENT')) {
            $resident = $user->resident;
            abort_unless($resident, 404);
            $query->where('resident_id', $resident->id);
        } elseif ($user->hasRole('SECURITY')) {
            $query->where('reported_by_user_id', $user->id);
        }
        $query->when($request->string('status')->isNotEmpty(), fn ($q) => $q->where('status', $request->string('status')))
            ->when($request->string('category')->isNotEmpty(), fn ($q) => $q->where('category', $request->string('category')))
            ->when($request->string('search')->isNotEmpty(), fn ($q) => $q->where(fn ($s) => $s->where('location', 'like', '%'.$request->string('search').'%')->orWhere('description', 'like', '%'.$request->string('search').'%')));

        return response()->json($query->latest()->paginate(20));
    }

    public function dashboard(Request $request)
    {
        abort_unless($request->user()->hasRole('ADMIN'), 403);
        $money = Penalty::query()->selectRaw('payment_status, SUM(disciplinary_amount + repair_cost + late_fee_amount) as total')
            ->groupBy('payment_status')->get()->mapWithKeys(fn ($row) => [$row->payment_status => (float) $row->total]);

        return response()->json(['data' => [
            'total_reports' => ViolationReport::count(),
            'by_status' => ViolationReport::query()->selectRaw('status, COUNT(*) as count')->groupBy('status')->pluck('count', 'status'),
            'by_category' => ViolationReport::query()->selectRaw('category, COUNT(*) as count')->groupBy('category')->pluck('count', 'category'),
            'financial_status' => $money,
        ]]);
    }

    public function show(Request $request, ViolationReport $report)
    {
        $this->authorizeReport($request, $report);

        return response()->json(['data' => $report->load(['rule', 'flat', 'resident.user:id,name', 'reporter:id,name', 'evidence:id,violation_report_id,original_name,mime_type,size_bytes', 'penalty.appeals', 'auditLogs.user:id,name'])]);
    }

    public function store(Request $request)
    {
        abort_unless($request->user()->hasRole('SECURITY'), 403);
        $data = $request->validate([
            'category' => ['required', Rule::in(array_keys(self::CATEGORIES))],
            'violation_type' => ['required', 'string', 'max:100'],
            'flat_id' => ['nullable', 'integer', 'exists:flats,id'],
            'vehicle_slot_id' => ['nullable', 'integer', 'exists:parking_slots,id'],
            'maintenance_bill_id' => ['nullable', 'integer', 'exists:maintenance_bills,id'],
            'booking_id' => ['nullable', 'integer', 'exists:amenity_bookings,id'],
            'incident_at' => ['required', 'date', 'before_or_equal:now'],
            'location' => ['required', 'string', 'max:255'], 'description' => ['required', 'string', 'max:5000'],
            'evidence' => ['sometimes', 'array', 'max:5'], 'evidence.*' => ['file', 'mimes:jpg,jpeg,png,webp,pdf', 'max:10240'],
        ]);
        if (! in_array($data['violation_type'], self::CATEGORIES[$data['category']], true)) {
            throw ValidationException::withMessages(['violation_type' => 'Violation type does not belong to the selected category.']);
        }
        $flatId = $data['flat_id'] ?? null;
        // A flat or parking slot identifies the incident location, not the person
        // responsible. The administrator must verify and select the resident.
        $residentId = null;
        if (! empty($data['vehicle_slot_id'])) {
            $slot = ParkingSlot::findOrFail($data['vehicle_slot_id']);
            if ($flatId && $slot->flat_id && (int) $flatId !== (int) $slot->flat_id) {
                abort(422, 'Vehicle slot does not belong to the selected flat.');
            }
            $flatId = $flatId ?: $slot->flat_id;
        }
        if (! empty($data['maintenance_bill_id'])) {
            $bill = MaintenanceBill::findOrFail($data['maintenance_bill_id']);
            if ($flatId && (int) $flatId !== (int) $bill->flat_id) {
                abort(422, 'Financial record does not belong to the selected flat.');
            }
            $flatId = $flatId ?: $bill->flat_id;
        }
        if (! empty($data['booking_id'])) {
            $booking = AmenityBooking::with('resident')->findOrFail($data['booking_id']);
            if ($flatId && (int) $flatId !== (int) $booking->resident?->flat_id) {
                abort(422, 'Booking does not belong to the selected flat.');
            }
            $flatId = $flatId ?: $booking->resident?->flat_id;
        }
        if (! $flatId && $data['category'] !== 'property_safety') {
            throw ValidationException::withMessages(['flat_id' => 'A related flat is required for this category.']);
        }
        $fingerprint = hash('sha256', implode('|', [
            $data['category'], $data['violation_type'], (string) ($flatId ?? 0),
            Carbon::parse($data['incident_at'])->utc()->format('Y-m-d H:i:s'),
            mb_strtolower(trim($data['location'])),
        ]));
        if (ViolationReport::where('incident_fingerprint', $fingerprint)->exists()) {
            throw ValidationException::withMessages(['incident_at' => 'This incident has already been reported.']);
        }

        try {
            return DB::transaction(function () use ($request, $data, $flatId, $residentId, $fingerprint) {
                $report = ViolationReport::create([...collect($data)->except('evidence')->all(), 'incident_fingerprint' => $fingerprint, 'flat_id' => $flatId, 'resident_id' => $residentId, 'rule_id' => null, 'reported_by_user_id' => $request->user()->id, 'status' => 'reported']);
                foreach ($request->file('evidence', []) as $file) {
                    $path = $file->store('penalties/'.$report->id, 'local');
                    $report->evidence()->create(['uploaded_by_user_id' => $request->user()->id, 'disk' => 'local', 'path' => $path, 'original_name' => $file->getClientOriginalName(), 'mime_type' => $file->getMimeType(), 'size_bytes' => $file->getSize()]);
                }
                $this->audit($report, $request->user()->id, 'reported', null, 'reported');

                return response()->json(['data' => $report->load('evidence:id,violation_report_id,original_name,mime_type,size_bytes')], 201);
            });
        } catch (QueryException $exception) {
            if (str_contains($exception->getMessage(), 'incident_fingerprint')) {
                throw ValidationException::withMessages(['incident_at' => 'This incident has already been reported.']);
            }
            throw $exception;
        }
    }

    public function decide(Request $request, ViolationReport $report)
    {
        abort_unless($request->user()->hasRole('ADMIN'), 403);
        if (! in_array($report->status, ['reported', 'under_review'], true)) {
            abort(422, 'This report has already been decided.');
        }
        $data = $request->validate([
            'decision' => ['required', Rule::in(['under_review', 'warning_issued', 'approved', 'rejected'])],
            'reason' => ['required', 'string', 'max:5000'],
            'disciplinary_amount' => ['required_if:decision,approved', 'numeric', 'gt:0', 'max:1000000'],
            'responsible_resident_id' => ['required_if:decision,approved', 'integer', 'exists:residents,id'],
            'repair_cost' => ['nullable', 'numeric', 'min:0'], 'due_date' => ['nullable', 'date', 'after_or_equal:today'],
        ]);
        $resident = isset($data['responsible_resident_id']) ? Resident::findOrFail($data['responsible_resident_id']) : null;
        if ($data['decision'] === 'approved' && (! $resident || ! $report->flat_id || (int) $resident->flat_id !== (int) $report->flat_id)) {
            throw ValidationException::withMessages(['responsible_resident_id' => 'Select a verified resident associated with the reported flat.']);
        }
        $lateFee = 0.0;
        $lateFeePeriod = null;
        $disciplinaryAmount = (float) ($data['disciplinary_amount'] ?? 0);
        if ($data['decision'] === 'approved' && (float) ($data['repair_cost'] ?? 0) > 0 && $report->evidence()->doesntExist()) {
            abort(422, 'Documented repair costs require supporting evidence.');
        }
        return DB::transaction(function () use ($request, $report, $data, $disciplinaryAmount, $lateFee, $lateFeePeriod, $resident) {
            $report = ViolationReport::query()->whereKey($report->id)->lockForUpdate()->firstOrFail();
            if (! in_array($report->status, ['reported', 'under_review'], true)) {
                abort(422, 'This report has already been decided.');
            }
            $from = $report->status;
            if ($data['decision'] === 'approved') {
                $report->resident_id = $resident->id;
            }
            $report->update(['status' => $data['decision']]);
            if ($data['decision'] === 'approved') {
                $penalty = Penalty::create(['violation_report_id' => $report->id, 'resident_id' => $resident->id, 'flat_id' => $resident->flat_id, 'disciplinary_amount' => $disciplinaryAmount, 'repair_cost' => $data['repair_cost'] ?? 0, 'late_fee_amount' => $lateFee, 'maintenance_bill_id' => $report->maintenance_bill_id, 'booking_id' => $report->booking_id, 'late_fee_period' => $lateFeePeriod, 'status' => 'approved', 'payment_status' => 'unpaid', 'due_date' => $data['due_date'] ?? null, 'decision_reason' => $data['reason'], 'decided_by_user_id' => $request->user()->id, 'decided_at' => now()]);
            }
            $this->audit($report, $request->user()->id, $data['decision'], $from, $data['decision'], $data['reason'], isset($penalty) ? ['disciplinary_amount' => $penalty->disciplinary_amount, 'late_fee_amount' => $penalty->late_fee_amount, 'repair_cost' => $penalty->repair_cost, 'late_fee_period' => $penalty->late_fee_period] : []);
            if ($data['decision'] !== 'under_review') {
                DB::afterCommit(fn () => $this->notifyResident($report->fresh(['resident.user']), 'penalty_'.$data['decision'], 'Violation report updated', $data['decision'] === 'approved' ? 'An approved penalty is available in your account.' : 'A decision has been recorded for a violation report.', ['report_id' => $report->id]));
            }

            return response()->json(['data' => $report->fresh()->load('penalty')]);
        });
    }

    public function rulesAdmin(Request $request)
    {
        abort_unless($request->user()->hasRole('ADMIN'), 403);

        return response()->json(['data' => PenaltyRule::orderBy('category')->orderBy('violation_type')->paginate(50)]);
    }

    public function saveRule(Request $request, ?PenaltyRule $rule = null)
    {
        abort_unless($request->user()->hasRole('ADMIN'), 403);
        $data = $request->validate(['category' => ['required', Rule::in(array_keys(self::CATEGORIES))], 'violation_type' => ['required', 'string', 'max:100'], 'description' => ['nullable', 'string', 'max:2000'], 'minimum_amount' => ['required', 'numeric', 'min:0'], 'maximum_amount' => ['nullable', 'numeric', 'gte:minimum_amount'], 'late_fee_amount' => ['nullable', 'numeric', 'min:0'], 'grace_period_days' => ['nullable', 'integer', 'min:0', 'max:365'], 'requires_evidence' => ['boolean'], 'active' => ['boolean']]);
        if (! in_array($data['violation_type'], self::CATEGORIES[$data['category']], true)) {
            throw ValidationException::withMessages(['violation_type' => 'Invalid violation type for category.']);
        }
        $rule ??= new PenaltyRule;
        $rule->fill([...$data, 'updated_by_user_id' => $request->user()->id])->save();

        return response()->json(['data' => $rule], $rule->wasRecentlyCreated ? 201 : 200);
    }

    public function appeal(Request $request, Penalty $penalty)
    {
        $resident = $request->user()->resident;
        abort_unless($request->user()->hasRole('RESIDENT') && $resident && $resident->id === $penalty->resident_id, 404);
        abort_unless($penalty->status === 'approved', 422, 'Only approved penalties may be appealed.');
        if ($penalty->appeals()->whereIn('status', ['submitted', 'under_review'])->exists()) {
            abort(422, 'An appeal is already open for this penalty.');
        }
        $data = $request->validate(['reason' => ['required', 'string', 'max:5000'], 'evidence' => ['sometimes', 'array', 'max:5'], 'evidence.*' => ['file', 'mimes:jpg,jpeg,png,webp,pdf', 'max:10240']]);
        $appeal = DB::transaction(function () use ($request, $penalty, $data) {
            $appeal = $penalty->appeals()->create(['resident_id' => $penalty->resident_id, 'reason' => $data['reason']]);
            $report = $penalty->report;
            foreach ($request->file('evidence', []) as $file) {
                $path = $file->store('penalties/'.$report->id, 'local');
                $report->evidence()->create(['appeal_id' => $appeal->id, 'uploaded_by_user_id' => $request->user()->id, 'disk' => 'local', 'path' => $path, 'original_name' => $file->getClientOriginalName(), 'mime_type' => $file->getMimeType(), 'size_bytes' => $file->getSize()]);
            }
            $report->update(['status' => 'appealed']);
            $this->audit($report, $request->user()->id, 'appeal_submitted', 'approved', 'appealed', $data['reason']);
            DB::afterCommit(fn () => $this->notifyAdmins($report));

            return $appeal;
        });

        return response()->json(['data' => $appeal], 201);
    }

    public function decideAppeal(Request $request, PenaltyAppeal $appeal)
    {
        abort_unless($request->user()->hasRole('ADMIN'), 403);
        abort_unless($appeal->status === 'submitted', 422, 'Appeal has already been decided.');
        $data = $request->validate(['decision' => ['required', Rule::in(['upheld', 'waived', 'adjusted', 'rejected'])], 'reason' => ['required', 'string', 'max:5000'], 'disciplinary_amount' => ['required_if:decision,adjusted', 'numeric', 'min:0']]);
        $penalty = $appeal->penalty()->with('report.rule')->firstOrFail();
        if (in_array($data['decision'], ['waived', 'adjusted'], true) && $penalty->payment_status === 'paid') {
            abort(422, 'A paid penalty requires a verified refund workflow before it can be waived or adjusted.');
        }
        if ($data['decision'] === 'adjusted' && ((float) $data['disciplinary_amount'] <= 0 || (float) $data['disciplinary_amount'] > 1000000)) {
            throw ValidationException::withMessages(['disciplinary_amount' => 'Enter an amount greater than zero and no more than 1,000,000.']);
        }

        return DB::transaction(function () use ($request, $appeal, $data) {
            $appeal = PenaltyAppeal::query()->whereKey($appeal->id)->lockForUpdate()->firstOrFail();
            if ($appeal->status !== 'submitted') {
                abort(422, 'Appeal has already been decided.');
            }
            $appeal->update(['status' => $data['decision'], 'decision_reason' => $data['reason'], 'decided_by_user_id' => $request->user()->id, 'decided_at' => now()]);
            $penalty = $appeal->penalty;
            $before = $penalty->status;
            if ($data['decision'] === 'waived') {
                $penalty->update(['status' => 'waived', 'payment_status' => 'waived']);
            } elseif ($data['decision'] === 'adjusted') {
                $penalty->update(['disciplinary_amount' => $data['disciplinary_amount'], 'status' => 'approved', 'payment_status' => 'unpaid']);
            }
            $report = $penalty->report;
            $report->update(['status' => 'resolved']);
            $this->audit($report, $request->user()->id, 'appeal_'.$data['decision'], $before, $penalty->status, $data['reason'], ['appeal_id' => $appeal->id]);
            DB::afterCommit(fn () => $this->notifyResident($report->fresh(['resident.user']), 'penalty_appeal_decided', 'Appeal decision recorded', 'Your penalty appeal has been decided. Open the penalty details to review the decision.', ['penalty_id' => $penalty->id, 'report_id' => $report->id]));

            return response()->json(['data' => $appeal->fresh()->load('penalty')]);
        });
    }

    public function evidence(Request $request, ViolationEvidence $evidence)
    {
        $report = $evidence->report;
        $this->authorizeReport($request, $report);
        abort_unless(Storage::disk($evidence->disk)->exists($evidence->path), 404);

        return Storage::disk($evidence->disk)->response($evidence->path, $evidence->original_name, ['Content-Type' => $evidence->mime_type, 'X-Content-Type-Options' => 'nosniff']);
    }

    public function appeals(Request $request)
    {
        abort_unless($request->user()->hasRole('ADMIN'), 403);

        return response()->json(PenaltyAppeal::with(['penalty.report', 'penalty.resident.user:id,name'])->latest()->paginate(20));
    }

    public function payment(Request $request, Penalty $penalty, PaymentOrderService $orders)
    {
        $resident = $request->user()->resident;
        abort_unless($request->user()->hasRole('RESIDENT') && $resident && $resident->id === $penalty->resident_id, 404);
        if ($penalty->status !== 'approved' || $penalty->payment_status !== 'unpaid') {
            abort(422, 'This penalty is not eligible for payment.');
        }
        try {
            $checkout = $orders->createRazorpayOrderForPenalty($resident, $penalty);
        } catch (PaymentGatewayUnavailableException $exception) {
            return response()->json(['message' => $exception->getMessage(), 'code' => 'PAYMENT_GATEWAY_NOT_CONFIGURED'], 503);
        }

        return response()->json(['message' => 'Penalty checkout order created. Payment will be recorded only after server verification.', 'data' => $checkout], 201);
    }

    private function authorizeReport(Request $request, ViolationReport $report): void
    {
        $user = $request->user();
        if ($user->hasRole('ADMIN')) {
            return;
        }
        if ($user->hasRole('SECURITY') && $report->reported_by_user_id === $user->id) {
            return;
        }
        if ($user->hasRole('RESIDENT') && $user->resident && (int) $user->resident->id === (int) $report->resident_id) {
            return;
        }
        abort(404);
    }

    private function audit(ViolationReport $report, int $userId, string $action, ?string $from, ?string $to, ?string $reason = null, array $details = []): void
    {
        PenaltyAuditLog::create(['violation_report_id' => $report->id, 'user_id' => $userId, 'action' => $action, 'from_status' => $from, 'to_status' => $to, 'reason' => $reason, 'details' => $details]);
    }

    private function notifyResident(ViolationReport $report, string $type, string $title, string $message, array $context): void
    {
        $report->resident?->user?->notify(new SocietyAlert($type, $title, $message, [...$context, 'audience' => 'RESIDENT']));
    }

    private function notifyAdmins(ViolationReport $report): void
    {
        User::where('role', 'ADMIN')->each(fn ($admin) => $admin->notify(new SocietyAlert('penalty_appeal_submitted', 'Penalty appeal submitted', 'A resident submitted an appeal for a penalty.', ['report_id' => $report->id, 'audience' => 'ADMIN'])));
    }
}
