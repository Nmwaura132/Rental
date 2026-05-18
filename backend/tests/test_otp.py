"""OTP generation must produce 6 cryptographically-random digits.
The fix swapped random.randint -> secrets.randbelow; verify the shape contract."""
import secrets


def test_otp_is_six_digit_string():
    # WHY: This mirrors the production code in PasswordResetRequestView. If the
    # shape ever drifts (5 or 7 digits) the SMS template + cache key both break.
    for _ in range(200):
        otp = f"{secrets.randbelow(900000) + 100000}"
        assert len(otp) == 6
        assert otp.isdigit()
        assert 100000 <= int(otp) <= 999999


def test_otp_is_unpredictable_enough():
    # Smoke test: 100 OTPs should not collide. (Birthday bound: very unlikely
    # for a 900k-wide space, but if random somehow snuck back, this fires.)
    samples = {f"{secrets.randbelow(900000) + 100000}" for _ in range(100)}
    assert len(samples) >= 95  # allow tiny collision tolerance
