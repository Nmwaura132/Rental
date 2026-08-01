from rest_framework.permissions import BasePermission


class IsLandlord(BasePermission):
    message = "Only landlords can perform this action."

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.is_landlord
        )


class IsLandlordOrCaretaker(BasePermission):
    message = "Only landlords and caretakers can perform this action."

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and (request.user.is_landlord or request.user.is_caretaker)
        )
