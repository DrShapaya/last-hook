using UnityEngine;

namespace LastHook
{
    public sealed class ExplorerView
    {
        public Transform Root;
        public Transform Body;
        public Transform LeftArm, RightArm;
        public Transform LeftLeg, RightLeg;
        public LineRenderer Rope;
        public LineRenderer RopeGlow;
        public Transform Bolt;
        private readonly MountainWorld world;

        public ExplorerView(MountainWorld world)
        {
            this.world=world;
            Root=new GameObject("Explorer").transform;
            Body=new GameObject("Body").transform;Body.SetParent(Root,false);
            var yellow=world.Mat("heroYellow",new Color(.98f,.64f,.17f));
            var dark=world.Mat("heroDark",new Color(.12f,.17f,.19f));
            var brown=world.Mat("backpackLeather",new Color(.34f,.26f,.14f));
            world.Box("Head",Vector3.zero,new Vector3(.66f,.63f,.57f),yellow,Body).transform.localPosition=new Vector3(0,.38f,-.1f);
            world.Box("Jacket",Vector3.zero,new Vector3(.52f,.55f,.42f),world.Mat("jacket",new Color(.23f,.32f,.26f)),Body).transform.localPosition=new Vector3(0,-.1f,0);
            world.Box("Backpack",Vector3.zero,new Vector3(.53f,.62f,.27f),brown,Body).transform.localPosition=new Vector3(-.34f,-.04f,.08f);
            for(int i=0;i<2;i++)
            {
                world.Box("Eye",Vector3.zero,new Vector3(.07f,.11f,.035f),dark,Body).transform.localPosition=new Vector3(-.12f+i*.23f,.43f,-.40f);
                world.Box("Backpack strap",Vector3.zero,new Vector3(.055f,.6f,.03f),world.Mat("strap",new Color(.64f,.48f,.24f)),Body).transform.localPosition=new Vector3(-.52f+i*.27f,-.04f,-.08f);
            }
            LeftArm=world.Box("Left arm",Vector3.zero,new Vector3(.15f,.42f,.16f),yellow,Body).transform;LeftArm.localPosition=new Vector3(-.32f,.03f,-.03f);
            RightArm=world.Box("Right arm",Vector3.zero,new Vector3(.15f,.42f,.16f),yellow,Body).transform;RightArm.localPosition=new Vector3(.32f,.03f,-.03f);
            LeftLeg=world.Box("Left leg",Vector3.zero,new Vector3(.16f,.28f,.20f),dark,Body).transform;LeftLeg.localPosition=new Vector3(-.15f,-.48f,0);
            RightLeg=world.Box("Right leg",Vector3.zero,new Vector3(.16f,.28f,.20f),dark,Body).transform;RightLeg.localPosition=new Vector3(.15f,-.48f,0);
            Rope=MakeRope("Rope",.045f,world.Mat("rope",new Color(.63f,.60f,1),true));
            RopeGlow=MakeRope("Rope glow",.105f,world.Mat("ropeOuter",new Color(.25f,.36f,.73f),true));
            Bolt=world.Primitive("Hook projectile",PrimitiveType.Sphere,Vector3.zero,new Vector3(.18f,.18f,.18f),world.Mat("hook",new Color(.63f,.92f,1),true),world.Root).transform;
            Bolt.gameObject.SetActive(false);
        }
        private LineRenderer MakeRope(string name,float width,Material material)
        {
            var line=new GameObject(name).AddComponent<LineRenderer>();line.transform.SetParent(world.Root);
            line.positionCount=2;line.startWidth=width;line.endWidth=width;line.sharedMaterial=material;line.useWorldSpace=true;line.numCapVertices=3;
            return line;
        }
        public void Draw(RopePhysics physics,Vector2 end,bool tether,bool projectile,float t)
        {
            Root.position=new Vector3(physics.Position.x,physics.Position.y,-.8f);
            float tilt=physics.Attached?Mathf.Clamp(-physics.Velocity.x*3,-35,35):Mathf.Clamp(-physics.Velocity.x*2,-25,25);
            Body.localRotation=Quaternion.Euler(0,-12,tilt);
            LeftArm.localRotation=Quaternion.Euler(0,0,physics.Attached?-150:-25);
            RightArm.localRotation=Quaternion.Euler(0,0,physics.Attached?150:25);
            LeftLeg.localRotation=Quaternion.Euler(0,0,Mathf.Sin(t*8)*12);
            RightLeg.localRotation=Quaternion.Euler(0,0,-Mathf.Sin(t*8)*12);
            Rope.enabled=tether;RopeGlow.enabled=tether;
            Vector3 from=Root.position+new Vector3(.15f,.2f,-.12f);
            Vector3 to=new Vector3(end.x,end.y,-.7f);
            if(tether){Rope.SetPosition(0,from);Rope.SetPosition(1,to);RopeGlow.SetPosition(0,from+Vector3.forward*.02f);RopeGlow.SetPosition(1,to+Vector3.forward*.02f);}
            Bolt.gameObject.SetActive(projectile);if(projectile)Bolt.position=to;
        }
    }
}
