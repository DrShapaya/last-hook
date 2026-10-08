using UnityEngine;

namespace LastHook
{
    // Gameplay physics runs in the XY plane; the scenery and character are 3D.
    public sealed class RopePhysics
    {
        public Vector2 Position;
        public Vector2 Velocity;
        public Vector2 Anchor;
        public bool Attached;
        public float Length;
        public float FlightPeak;
        public float Highest;
        public bool LeftGround;
        public bool OnPlatform;

        public void Attach(Vector2 anchor, float maximumLength)
        {
            Anchor = anchor;
            Length = Mathf.Clamp(Vector2.Distance(Position, anchor), 1.1f, maximumLength);
            Attached = true; OnPlatform = false; LeftGround = true;
            Vector2 radial = (Position - Anchor).normalized;
            Velocity -= radial * Mathf.Max(0, Vector2.Dot(Velocity, radial));
            Velocity *= .96f;
            if (Velocity.sqrMagnitude < .7f) Velocity += new Vector2(-radial.y, radial.x) * 1.3f;
            FlightPeak = Position.y;
        }

        public void Release(float impulseFactor)
        {
            if (!Attached) return;
            Attached = false;
            // Boost once per release; attachment dissipates energy and speed is capped.
            Velocity = Vector2.ClampMagnitude(Velocity * impulseFactor, 18f);
            FlightPeak = Position.y;
        }

        public void Tick(float dt, float pump, float reel)
        {
            Vector2 acceleration = Vector2.down * GameRules.Gravity;
            if (Attached)
            {
                Vector2 radial = (Position - Anchor).normalized;
                Vector2 force = Vector2.right * pump * 10f;
                acceleration += force - radial * Vector2.Dot(force, radial);
                if (reel > 0) Length = Mathf.Max(1.5f, Length - reel * 1.5f * dt);
            }
            Velocity += acceleration * dt;
            Velocity *= Mathf.Exp(-.065f * dt);
            Velocity = Vector2.ClampMagnitude(Velocity, 18f);
            Position += Velocity * dt;
            if (Attached)
            {
                Vector2 offset = Position - Anchor;
                float distance = offset.magnitude;
                if (distance > Length && distance > .001f)
                {
                    Vector2 radial = offset / distance;
                    Position = Anchor + radial * Length;
                    Velocity -= radial * Mathf.Max(0, Vector2.Dot(Velocity, radial));
                }
            }
            else FlightPeak = Mathf.Max(FlightPeak, Position.y);
            Highest = Mathf.Max(Highest, Position.y);
        }

        public float Fallen { get { return Attached || OnPlatform ? 0 : Mathf.Max(0, FlightPeak - Position.y); } }
        public bool FallExpired { get { return LeftGround && !Attached && !OnPlatform && Fallen >= GameRules.FallLimitUnits; } }

        public void Land(float top)
        {
            Position = new Vector2(Position.x, top + .48f);
            Velocity = new Vector2(Velocity.x * .78f, 0);
            OnPlatform = true; FlightPeak = Position.y;
        }

        public static bool SegmentCircle(Vector2 from, Vector2 to, Vector2 center, float radius, out float fraction)
        {
            Vector2 delta = to - from;
            float lengthSquared = delta.sqrMagnitude;
            if (lengthSquared < .000001f) { fraction = 0; return Vector2.Distance(from, center) <= radius; }
            float b = Vector2.Dot(from - center, delta);
            float c = (from - center).sqrMagnitude - radius * radius;
            if (c <= 0) { fraction = 0; return true; }
            float discriminant = b * b - lengthSquared * c;
            if (discriminant < 0) { fraction = 0; return false; }
            fraction = (-b - Mathf.Sqrt(discriminant)) / lengthSquared;
            return fraction >= 0 && fraction <= 1;
        }
    }
}
