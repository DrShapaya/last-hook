"""The hero's joints (hero units: height 1.0, origin between the feet, the
hero looks along +X, the camera side is -Y, Z is up). One place for the model
(build_hero.py) and the skeleton (export_hero.py): they must match.

Version 2.0 proportions follow reference-v2.png: a slightly smaller head,
a longer, slimmer body and longer legs than the first model.
"""
from mathutils import Vector

HEAD_TOP = 1.0
HEAD_BOTTOM = 0.738
NECK = 0.712
SHOULDER = (-0.006, 0.664)  # (x, z)
ELBOW = (0.004, 0.556)
WRIST = (0.03, 0.452)  # The forearm hangs a little forward.
HIP = 0.452
KNEE = 0.266
ANKLE = 0.086
ARM_Y = 0.146  # Shoulder distance from the body centre line.
LEG_Y = 0.068  # Leg centre lines.


def arm_points(side):
    """Shoulder, elbow and wrist of one arm: hanging relaxed, the elbow a
    little out and back, the forearm slightly forward."""
    k = 1 if side == "near" else -1
    y = -ARM_Y * k
    sh = Vector((SHOULDER[0], y, SHOULDER[1]))
    el = Vector((ELBOW[0], y - 0.01 * k, ELBOW[1]))
    wr = Vector((WRIST[0], y - 0.02 * k, WRIST[1]))  # Hands clear the hips and the jacket hem.
    return sh, el, wr


def leg_points(side):
    y = -LEG_Y if side == "near" else LEG_Y
    return Vector((-0.004, y, HIP)), Vector((0.012, y, KNEE)), Vector((0.0, y, ANKLE))
