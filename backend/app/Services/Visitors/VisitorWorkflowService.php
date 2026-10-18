<?php

namespace App\Services\Visitors;

use App\Mail\VisitorApprovalRequested;
use App\Models\Flat;
use App\Models\Resident;
use App\Models\User;
use App\Models\Visitor;
use App\Notifications\SocietyAlert;
use App\Notifications\VisitorAwaitingApproval;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Validation\ValidationException;

class VisitorWorkflowService
{
    public function createGateRequest(User $securityUser, array $data): Visitor
    {
        $flatId = (int) $data['flat_id'];
        $flat = Flat::find($flatId);

        if (! $flat) {
            throw ValidationException::withMessages(['flat_id' => 'The selected flat does not exist.']);
        }

        $residentId = isset($data['resident_id']) && $data['resident_id'] ? (int) $data['resident_id'] : null;

        if ($residentId) {
            $resident = Resident::where('id', $residentId)->where('flat_id', $flatId)->first()
                ?? Resident::where('id', $residentId)->first()
                ?? Resident::where('flat_id', $flatId)->where('is_primary_contact', true)->first()
                ?? Resident::where('flat_id', $flatId)->first();
        } else {
            $resident = Resident::where('flat_id', $flatId)->where('is_primary_contact', true)->first()
                ?? Resident::where('flat_id', $flatId)->first();
        }

        if (! $resident) {
            throw ValidationException::withMessages(['flat_id' => 'Resident for this flat was not found.']);
        }

        $residentUser = $resident->user;

        if (! $residentUser || empty($residentUser->email)) {
            throw ValidationException::withMessages(['resident_id' => 'Resident email address is not configured.']);
        }

        $visitor = DB::transaction(function () use ($securityUser, $data, $flat, $resident): Visitor {
            return Visitor::create([
                'visitor_name' => $data['visitor_name'],
                'flat_id' => $flat->id,
                'resident_id' => $resident->id,
                'visitor_type' => $data['visitor_type'],
                'entry_status' => Visitor::ENTRY_WAITING,
                'approval_status' => Visitor::APPROVAL_PENDING,
                'created_by_security_id' => $securityUser->id,
            ]);
        });

        // Masked email for safe logging (never log full sensitive email or credentials)
        $email = (string) $residentUser->email;
        $maskedEmail = preg_replace('/(?<=.{2}).(?=.*@)/u', '*', $email);

        // In-app notifications: notify the selected resident and all co-residents associated with this flat
        $notificationId = null;
        $visitor->setRelation('flat', $flat);
        $flatResidents = Resident::where('flat_id', $flat->id)->with('user')->get();
        if ($resident && ! $flatResidents->contains('id', $resident->id)) {
            $flatResidents->push($resident);
        }

        $notifiedUserIds = [];
        foreach ($flatResidents as $targetResident) {
            $u = $targetResident->user;
            if ($u && ! in_array($u->id, $notifiedUserIds, true)) {
                $notifiedUserIds[] = $u->id;
                try {
                    $u->notify(new VisitorAwaitingApproval($visitor));
                    if ($u->id === $residentUser->id || $notificationId === null) {
                        $dbNotification = $u->notifications()->latest()->first();
                        $notificationId = $dbNotification?->id;
                    }
                } catch (\Throwable $e) {
                    Log::warning('IN-APP NOTIFICATION FAILED', ['user_id' => $u->id, 'error' => $e->getMessage()]);
                }
            }
        }

        Log::info('VISITOR NOTIFICATION DEBUG', [
            'Visitor ID' => $visitor->id,
            'Resident ID' => $resident->id,
            'User ID' => $residentUser->id,
            'Flat' => $flat->flat_number,
            'Building' => $flat->building,
            'Resident email' => $maskedEmail,
            'Notification created' => $notificationId ? 'YES' : 'NO',
            'Notification ID' => $notificationId,
        ]);


        // Email notification with signed one-click action links (valid for 24 hours)
        try {
            $approveUrl = \Illuminate\Support\Facades\URL::temporarySignedRoute(
                'visitor.action',
                now()->addHours(24),
                ['visitor' => $visitor->id, 'action' => 'approve']
            );

            $rejectUrl = \Illuminate\Support\Facades\URL::temporarySignedRoute(
                'visitor.action',
                now()->addHours(24),
                ['visitor' => $visitor->id, 'action' => 'reject']
            );

            $mailHost = (string) config('mail.mailers.smtp.host');
            $mailPort = (string) config('mail.mailers.smtp.port');
            $mailEnc = (string) config('mail.mailers.smtp.encryption');

            Log::info('VISITOR EMAIL DELIVERY ATTEMPT', [
                'Visitor ID' => $visitor->id,
                'Resident ID' => $resident->id,
                'Recipient' => $maskedEmail,
                'Mail Class' => \App\Mail\VisitorApprovalRequested::class,
                'SMTP Host' => $mailHost,
                'SMTP Port' => $mailPort,
                'SMTP Encryption' => $mailEnc,
            ]);

            Mail::to($residentUser->email)->send(new VisitorApprovalRequested(
                visitorName: $visitor->visitor_name,
                visitorType: $visitor->visitor_type,
                flatNumber: (string) $flat->flat_number,
                building: (string) $flat->building,
                requestStatus: 'Waiting for approval',
                requestedAt: now()->format('d M Y, h:i A'),
                residentName: $residentUser->name,
                approveUrl: $approveUrl,
                rejectUrl: $rejectUrl,
            ));

            Log::info('VISITOR EMAIL DELIVERY', [
                'Visitor ID' => $visitor->id,
                'Resident ID' => $resident->id,
                'Recipient' => $maskedEmail,
                'Mail Class' => \App\Mail\VisitorApprovalRequested::class,
                'SMTP Host' => $mailHost,
                'SMTP Port' => $mailPort,
                'SMTP Encryption' => $mailEnc,
                'SMTP Accepted' => 'SUCCESS',
            ]);
        } catch (\Throwable $e) {
            Log::error('VISITOR EMAIL DELIVERY FAILED', [
                'Visitor ID' => $visitor->id,
                'Resident ID' => $resident->id,
                'Recipient' => $maskedEmail,
                'SMTP Host' => config('mail.mailers.smtp.host'),
                'SMTP Accepted' => 'FAIL',
                'Error' => $e->getMessage(),
            ]);
        }

        return $visitor->load(['flat', 'resident.user']);
    }




    public function createPreApproval(Resident $resident, array $data): Visitor
    {
        return Visitor::create([
            ...Arr::only($data, ['visitor_name', 'visitor_type', 'expected_at']),
            'flat_id' => $resident->flat_id,
            'resident_id' => $resident->id,
            'entry_status' => Visitor::ENTRY_EXPECTED,
            'approval_status' => Visitor::APPROVAL_APPROVED,
            'approved_at' => now(),
            'approved_by_resident_id' => $resident->id,
            'is_pre_approved' => true,
        ]);
    }

    public function approve(Visitor $visitor, Resident $resident): Visitor
    {
        $this->ensurePending($visitor);

        $visitor->update([
            'approval_status' => Visitor::APPROVAL_APPROVED,
            'approved_at' => now(),
            'approved_by_resident_id' => $resident->id,
        ]);

        $visitor->createdBySecurity?->notify(new SocietyAlert(
            'visitor_approved',
            'Visitor approved',
            sprintf('%s was approved by the resident.', $visitor->visitor_name),
            ['visitor_id' => $visitor->id, 'visitor_name' => $visitor->visitor_name],
        ));

        return $visitor->fresh(['flat', 'resident']);
    }


    public function reject(Visitor $visitor, Resident $resident, ?string $reason): Visitor
    {
        $this->ensurePending($visitor);

        $visitor->update([
            'approval_status' => Visitor::APPROVAL_REJECTED,
            'approval_note' => $reason,
            'approved_at' => now(),
            'approved_by_resident_id' => $resident->id,
        ]);

        $visitor->createdBySecurity?->notify(new SocietyAlert(
            'visitor_rejected',
            'Visitor declined',
            sprintf('%s was declined by the resident.', $visitor->visitor_name),
            ['visitor_id' => $visitor->id, 'visitor_name' => $visitor->visitor_name],
        ));

        return $visitor->fresh(['flat', 'resident']);
    }


    public function recordEntry(Visitor $visitor): Visitor
    {
        $result = DB::transaction(function () use ($visitor): Visitor {
            /** @var Visitor|null $lockedVisitor */
            $lockedVisitor = Visitor::where('id', $visitor->id)->lockForUpdate()->first();

            if (! $lockedVisitor || $lockedVisitor->approval_status !== Visitor::APPROVAL_APPROVED || $lockedVisitor->entered_at !== null || $lockedVisitor->entry_status === Visitor::ENTRY_ENTERED) {
                throw ValidationException::withMessages(['visitor' => 'Only an approved visitor who has not entered can be recorded as entered.']);
            }

            $lockedVisitor->update([
                'entry_status' => Visitor::ENTRY_ENTERED,
                'entered_at' => now(),
            ]);

            $lockedVisitor->resident?->user?->notify(new SocietyAlert(
                'visitor_checked_in',
                'Visitor checked in',
                sprintf('%s has entered the society.', $lockedVisitor->visitor_name),
                ['visitor_id' => $lockedVisitor->id, 'visitor_name' => $lockedVisitor->visitor_name],
            ));

            return $lockedVisitor->fresh(['flat', 'resident']);
        });

        return $result;
    }


    public function recordExit(Visitor $visitor): Visitor
    {
        $result = DB::transaction(function () use ($visitor): Visitor {
            /** @var Visitor|null $lockedVisitor */
            $lockedVisitor = Visitor::where('id', $visitor->id)->lockForUpdate()->first();

            if (! $lockedVisitor || $lockedVisitor->entry_status !== Visitor::ENTRY_ENTERED || $lockedVisitor->exited_at !== null) {
                throw ValidationException::withMessages(['visitor' => 'Only a visitor currently inside can be recorded as exited.']);
            }

            $lockedVisitor->update([
                'entry_status' => Visitor::ENTRY_EXITED,
                'approval_status' => Visitor::APPROVAL_COMPLETED,
                'exited_at' => now(),
            ]);

            $lockedVisitor->resident?->user?->notify(new SocietyAlert(
                'visitor_checked_out',
                'Visitor checked out',
                sprintf('%s has exited the society.', $lockedVisitor->visitor_name),
                ['visitor_id' => $lockedVisitor->id, 'visitor_name' => $lockedVisitor->visitor_name],
            ));

            return $lockedVisitor->fresh(['flat', 'resident']);
        });

        return $result;
    }


    private function ensurePending(Visitor $visitor): void
    {
        if ($visitor->approval_status !== Visitor::APPROVAL_PENDING) {
            throw ValidationException::withMessages(['visitor' => 'Only a pending visitor request can be actioned.']);
        }
    }
}
