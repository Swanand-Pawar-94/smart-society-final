<?php

namespace App\Http\Controllers\Api\Visitors;

use App\Http\Controllers\Controller;
use App\Models\Resident;
use App\Models\Visitor;
use App\Notifications\VisitorAwaitingApproval;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Compatibility endpoint for security staff creating visitor requests.
 */
class VisitorRequestController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'visitor_name'  => ['required', 'string', 'max:120'],
            'mobile_number' => ['nullable', 'string', 'max:25'],
            'purpose'       => ['nullable', 'string', 'max:255'],
            'visitor_type'  => ['nullable', 'string', 'in:GUEST,DELIVERY,CAB,SERVICE_PROVIDER,OTHER'],
            // flat_id is optional - if omitted we use the authenticated resident's flat
            'flat_id'       => ['nullable', 'integer', 'exists:flats,id'],
            'resident_id'   => ['nullable', 'integer', 'exists:residents,id'],
        ]);

        $user = $request->user();

        // Resolve resident & flat ─────────────────────────────────────────────
        if (! empty($validated['resident_id'])) {
            $resident = Resident::with('flat', 'user')
                ->whereKey($validated['resident_id'])
                ->when(! empty($validated['flat_id']), fn ($query) => $query->where('flat_id', $validated['flat_id']))
                ->first();
        } elseif (! empty($validated['flat_id'])) {
            $resident = Resident::with('flat', 'user')
                ->where('flat_id', $validated['flat_id'])
                ->where('is_primary_contact', true)
                ->first()
                ?? Resident::with('flat', 'user')->where('flat_id', $validated['flat_id'])->first();
        } else {
            // Fall back to the authenticated user's own resident record
            $resident = Resident::with('flat', 'user')
                ->where('user_id', $user->id)
                ->first();
        }

        if (! $resident || ! $resident->flat) {
            return response()->json([
                'message' => 'Could not determine a resident/flat for this request. ' .
                    'Pass flat_id or resident_id, or ensure the authenticated user is linked to a flat.',
                'errors'  => ['flat_id' => ['No matching flat/resident found.']],
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        // Create visitor record ───────────────────────────────────────────────
        $visitor = Visitor::create([
            'visitor_name'          => $validated['visitor_name'],
            'mobile_number'         => $validated['mobile_number'] ?? null,
            'purpose'               => $validated['purpose'] ?? 'Test visitor request',
            'visitor_type'          => $validated['visitor_type'] ?? Visitor::TYPE_GUEST,
            'flat_id'               => $resident->flat_id,
            'resident_id'           => $resident->id,
            'entry_status'          => Visitor::ENTRY_WAITING,
            'approval_status'       => Visitor::APPROVAL_PENDING,
            'created_by_security_id' => $user->id,
        ]);

        $visitor->setRelation('flat', $resident->flat);
        $residentUser = $resident->user;
        if ($residentUser) {
            $residentUser->notify(new VisitorAwaitingApproval($visitor));
        }

        return response()->json([
            'message' => 'Visitor request created successfully.',
            'data'    => [
                'visitor'       => [
                    'id'              => $visitor->id,
                    'visitor_name'    => $visitor->visitor_name,
                    'mobile_number'   => $visitor->mobile_number,
                    'purpose'         => $visitor->purpose,
                    'visitor_type'    => $visitor->visitor_type,
                    'approval_status' => $visitor->approval_status,
                    'entry_status'    => $visitor->entry_status,
                    'flat_id'         => $visitor->flat_id,
                    'flat_number'     => $resident->flat->flat_number ?? null,
                    'building'        => $resident->flat->building ?? null,
                    'resident_id'     => $visitor->resident_id,
                    'created_at'      => $visitor->created_at,
                ],
                'notification' => $residentUser ? 'persisted' : 'skipped_no_resident_user',
            ],
        ], Response::HTTP_CREATED);
    }
}
