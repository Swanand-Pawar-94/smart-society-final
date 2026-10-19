<?php

namespace App\Http\Controllers\Api\Options;

use App\Http\Controllers\Controller;
use App\Models\Amenity;
use App\Models\Flat;
use App\Models\Resident;
use App\Models\StaffMember;
use App\Models\User;
use App\Models\ParkingSlot;
use Illuminate\Http\JsonResponse;

class SelectionOptionsController extends Controller
{
    public function admin(): JsonResponse
    {
        return response()->json(['data' => $this->options(includeOwners: true, includeStaff: true)]);
    }

    public function staff(): JsonResponse
    {
        return response()->json(['data' => $this->options()]);
    }

    public function security(): JsonResponse
    {
        return response()->json(['data' => $this->options(includeParking: true)]);
    }

    private function options(bool $includeOwners = false, bool $includeStaff = false, bool $includeParking = false): array
    {
        $data = [
            'flats' => Flat::query()->orderBy('building')->orderBy('flat_number')
                ->get(['id', 'flat_number', 'building'])
                ->map(fn (Flat $flat) => [
                    'id' => $flat->id,
                    'label' => "Flat {$flat->flat_number} - Building {$flat->building}",
                ]),
            'residents' => Resident::query()->with(['user:id,name,email', 'flat:id,flat_number,building'])->orderBy('id')->get()
                ->map(fn (Resident $resident) => [
                    'id' => $resident->id,
                    'flat_id' => $resident->flat_id,
                    'label' => "{$resident->user->name} - Flat {$resident->flat->flat_number} ({$resident->flat->building})",
                ]),
            'amenities' => Amenity::query()->where('is_active', true)->orderBy('name')->get(['id', 'name'])
                ->map(fn (Amenity $amenity) => ['id' => $amenity->id, 'label' => $amenity->name]),
        ];

        if ($includeParking) {
            $data['parking_slots'] = ParkingSlot::query()->with('flat:id,flat_number,building')->orderBy('slot_number')->get(['id', 'slot_number', 'flat_id', 'vehicle_number'])->map(fn (ParkingSlot $slot) => [
                'id' => $slot->id,
                'label' => trim($slot->slot_number.' · '.($slot->vehicle_number ?: 'Unregistered vehicle').' · '.($slot->flat ? "Flat {$slot->flat->flat_number}" : 'Visitor or unassigned')),
            ]);
        }

        if ($includeOwners) {
            $data['owners'] = User::query()->where('role', User::ROLE_RESIDENT)->orderBy('name')
                ->get(['id', 'name', 'email'])
                ->map(fn (User $user) => ['id' => $user->id, 'label' => "{$user->name} - {$user->email}"]);
        }

        if ($includeStaff) {
            $data['staff_members'] = StaffMember::query()->where('status', 'ACTIVE')->orderBy('name')
                ->get(['id', 'name', 'designation'])
                ->map(fn (StaffMember $staff) => ['id' => $staff->id, 'label' => "{$staff->name} - {$staff->designation}"]);
        }

        return $data;
    }
}
