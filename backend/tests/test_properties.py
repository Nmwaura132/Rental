"""Units: the house numbers a landlord sets, and the payment code that follows them."""

import pytest


class TestRenamingAUnit:
    """The landlord sets house numbers; the code tenants pay to must follow."""

    def test_the_payment_code_follows_a_new_house_number(self, unit):
        unit.unit_number = "G7"
        unit.save()
        assert unit.payment_code == "G7"

    def test_a_partial_save_of_the_number_still_updates_the_code(self, unit):
        from apps.properties.models import Unit

        unit.unit_number = "G8"
        unit.save(update_fields=["unit_number"])
        assert Unit.objects.get(pk=unit.pk).payment_code == "G8"

    def test_changing_only_the_case_does_not_add_a_suffix(self, unit):
        unit.unit_number = unit.unit_number.lower()
        unit.save()
        assert unit.payment_code.upper() == unit.unit_number.upper()

    def test_saving_without_renaming_keeps_the_code(self, unit):
        before = unit.payment_code
        unit.rent_amount += 1
        unit.save()
        assert unit.payment_code == before


class TestRenumberingAProperty:
    """Maria Goretti's units, created as 101, 102..., moved onto G1, G2, 1A...
    in one step."""

    @pytest.fixture
    def units(self, property_):
        from decimal import Decimal

        from apps.properties.models import Unit

        return [
            Unit.objects.create(
                property=property_, unit_number=n, unit_type=Unit.UnitType.BEDSITTER,
                rent_amount=Decimal("10000"), deposit_amount=Decimal("10000"), floor=f,
            )
            for n, f in [("101", 0), ("102", 0), ("201", 1), ("202", 1)]
        ]

    @pytest.fixture
    def client(self, landlord):
        from rest_framework.test import APIClient

        api = APIClient()
        api.force_authenticate(user=landlord)
        return api

    def _renumber(self, client, property_, mapping):
        return client.post(
            f"/api/v1/properties/{property_.id}/renumber/",
            {"units": [{"id": u.id, "unit_number": n} for u, n in mapping]},
            format="json",
        )

    def test_every_unit_gets_its_new_number(self, client, property_, units):
        self._renumber(client, property_, zip(units, ["G1", "G2", "1A", "1B"]))
        assert [u.unit_number for u in property_.units.order_by("id")] == ["G1", "G2", "1A", "1B"]

    def test_payment_codes_follow(self, client, property_, units):
        self._renumber(client, property_, zip(units, ["G1", "G2", "1A", "1B"]))
        assert [u.payment_code for u in property_.units.order_by("id")] == ["G1", "G2", "1A", "1B"]

    def test_two_units_can_trade_numbers(self, client, property_, units):
        # The case renaming one at a time cannot do.
        response = self._renumber(client, property_, [(units[0], "102"), (units[1], "101")])
        assert response.status_code == 200

    def test_a_repeated_number_is_refused(self, client, property_, units):
        response = self._renumber(client, property_, [(units[0], "G1"), (units[1], "g1")])
        assert response.status_code == 400

    def test_a_refused_renumber_changes_nothing(self, client, property_, units):
        self._renumber(client, property_, [(units[0], "G1"), (units[1], "G1")])
        assert property_.units.order_by("id").first().unit_number == "101"

    def test_a_clash_with_a_unit_left_out_is_refused(self, client, property_, units):
        response = self._renumber(client, property_, [(units[0], "201")])
        assert response.status_code == 400

    def test_another_landlords_units_cannot_be_touched(self, client, property_, units, django_user_model):
        from apps.properties.models import Property

        stranger = django_user_model.objects.create_user(
            phone_number="+254700333444", password="Other@Test1",
            first_name="O", last_name="L", role=django_user_model.Role.LANDLORD,
        )
        theirs = Property.objects.create(owner=stranger, name="Not Yours")
        response = client.post(f"/api/v1/properties/{theirs.id}/renumber/", {"units": []}, format="json")
        assert response.status_code == 404

    def test_a_caretaker_cannot_renumber(self, property_, units, caretaker):
        from rest_framework.test import APIClient

        property_.caretaker = caretaker
        property_.save(update_fields=["caretaker"])
        api = APIClient()
        api.force_authenticate(user=caretaker)
        response = api.post(f"/api/v1/properties/{property_.id}/renumber/", {"units": []}, format="json")
        assert response.status_code == 403
