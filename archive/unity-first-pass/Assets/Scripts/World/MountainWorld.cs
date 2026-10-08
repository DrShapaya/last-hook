using System;
using System.Collections.Generic;
using UnityEngine;

namespace LastHook
{
    public sealed class AnchorPoint
    {
        public int Id;
        public Vector2 Position;
        public MaterialKind Kind;
        public bool Broken;
        public Transform Visual;
        public Renderer Glow;
    }
    public sealed class WorldLoot
    {
        public LootItem Item;
        public Vector2 Position;
        public Transform Visual;
    }
    public struct Ledge
    {
        public float Left, Right, Top;
        public Ledge(float left, float right, float top) { Left = left; Right = right; Top = top; }
    }

    public sealed class MountainWorld
    {
        public readonly List<AnchorPoint> Anchors = new List<AnchorPoint>();
        public readonly List<WorldLoot> Loot = new List<WorldLoot>();
        public readonly List<Ledge> Ledges = new List<Ledge>();
        public readonly List<Transform> CloudTransforms = new List<Transform>();
        public Transform Root;
        public Transform StaticRoot;
        public float GeneratedHeight;
        private readonly Dictionary<string, Material> materials = new Dictionary<string, Material>();
        private readonly int seed;
        private readonly int location;
        private int mainIndex;
        private int anchorId;
        private int lootId;
        private int sceneryChunk;

        public MountainWorld(int seed, int location)
        {
            this.seed = seed; this.location = location;
            Root = new GameObject("Mountain").transform;
            StaticRoot = new GameObject("Scenery").transform; StaticRoot.SetParent(Root);
            Ledges.Add(new Ledge(-5.8f, 5.8f, .15f));
            Rock(new Vector3(0, -1.9f, 1.2f), new Vector3(6.9f, 2.1f, 3), 1001, StoneColor(0));
            Box("Start ledge", new Vector3(0, .03f, -.1f), new Vector3(11.6f, .3f, 2.2f), Mat("wood", new Color(.34f, .22f, .13f)));
            Grass(new Vector3(-3.9f, .3f, -.7f), 2, 551);
            Grass(new Vector3(3.9f, .3f, -.7f), 2, 552);
        }

        public Material Mat(string key, Color color, bool unlit = false)
        {
            Material result;
            if (materials.TryGetValue(key, out result)) return result;
            result = new Material(Shader.Find(unlit ? "Unlit/Color" : "Standard"));
            result.color = color;
            if (!unlit) { result.SetFloat("_Glossiness", .08f); result.SetFloat("_Metallic", 0); }
            materials[key] = result;
            return result;
        }

        public Color StoneColor(int zone)
        {
            if (location == 1) return Color.Lerp(new Color(.29f, .32f, .38f), new Color(.48f, .50f, .56f), zone / 8f);
            if (location == 2) return new Color(.42f, .36f, .28f);
            Color[] colors = { new Color(.37f,.36f,.29f), new Color(.35f,.38f,.41f), new Color(.47f,.38f,.28f), new Color(.48f,.59f,.63f), new Color(.28f,.25f,.28f), new Color(.65f,.58f,.49f) };
            return colors[Mathf.Clamp(zone, 0, 5)];
        }

        public GameObject Primitive(string name, PrimitiveType type, Vector3 position, Vector3 scale, Material material, Transform parent = null)
        {
            var go = GameObject.CreatePrimitive(type); go.name = name;
            go.transform.SetParent(parent == null ? StaticRoot : parent);
            go.transform.position = position; go.transform.localScale = scale;
            go.GetComponent<Renderer>().sharedMaterial = material;
            UnityEngine.Object.Destroy(go.GetComponent<Collider>());
            return go;
        }
        public GameObject Box(string name, Vector3 position, Vector3 scale, Material material, Transform parent = null)
        { return Primitive(name, PrimitiveType.Cube, position, scale, material, parent); }

        public GameObject Rock(Vector3 position, Vector3 scale, int salt, Color color)
        {
            var random = new System.Random(seed ^ salt);
            const int sides = 7;
            const int rings = 4;
            var points = new List<Vector3>();
            var faces = new List<int>();
            for (int ring = 0; ring < rings; ring++)
            {
                float y = -1f + ring * 2f / (rings - 1);
                for (int side = 0; side < sides; side++)
                {
                    float angle = side * Mathf.PI * 2f / sides + (ring % 2 == 0 ? .08f : -.1f);
                    float radius = (.78f + (float)random.NextDouble() * .25f) * (ring == 0 || ring == rings - 1 ? .80f : 1f);
                    points.Add(new Vector3(Mathf.Cos(angle) * radius, y + ((float)random.NextDouble() - .5f) * .18f, Mathf.Sin(angle) * radius));
                }
            }
            for (int ring = 0; ring < rings - 1; ring++)
            for (int side = 0; side < sides; side++)
            {
                int a = ring * sides + side, b = ring * sides + (side + 1) % sides;
                int c = a + sides, d = b + sides;
                faces.Add(a); faces.Add(c); faces.Add(b); faces.Add(b); faces.Add(c); faces.Add(d);
            }
            for (int side = 1; side < sides - 1; side++)
            { faces.Add(0); faces.Add(side); faces.Add(side + 1); faces.Add((rings - 1) * sides); faces.Add((rings - 1) * sides + side + 1); faces.Add((rings - 1) * sides + side); }
            // Duplicate triangle vertices for a faceted surface.
            var flat = new Vector3[faces.Count]; var triangles = new int[faces.Count];
            for (int i = 0; i < faces.Count; i++) { flat[i] = points[faces[i]]; triangles[i] = i; }
            Mesh mesh = new Mesh(); mesh.name = "Faceted rock"; mesh.vertices = flat; mesh.triangles = triangles; mesh.RecalculateNormals();
            var go = new GameObject("Rock"); go.transform.SetParent(StaticRoot); go.transform.position = position; go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            int palette = Mathf.Abs(salt) % 4;
            go.AddComponent<MeshRenderer>().sharedMaterial = Mat("stone" + GameRules.ZoneAt(position.y) + "_" + palette, color * (.86f + palette * .065f));
            return go;
        }

        private void Grass(Vector3 center, float radius, int salt)
        {
            var random = new System.Random(seed ^ salt);
            for (int i = 0; i < 13; i++)
            {
                float x = ((float)random.NextDouble() - .5f) * radius * 2;
                float z = ((float)random.NextDouble() - .5f) * radius;
                var leaf = Primitive("Moss", PrimitiveType.Sphere, center + new Vector3(x, (float)random.NextDouble() * .20f, z), new Vector3(.6f, .18f, .4f), Mat("green" + i % 3, new Color(.25f + .06f * (i % 3), .42f + .055f * (i % 3), .12f)));
                leaf.transform.rotation = Quaternion.Euler(0, random.Next(360), random.Next(-20,20));
            }
            for (int i = 0; i < 5; i++)
            {
                var fern = Box("Fern", center + new Vector3(((float)random.NextDouble() - .5f) * radius, .28f, -.35f), new Vector3(.08f, .8f, .07f), Mat("fern", new Color(.54f,.62f,.17f)));
                fern.transform.rotation = Quaternion.Euler(0, 20, -30 + i * 15);
            }
        }

        private void Tree(Vector3 position, int salt)
        {
            var brown = Mat("trunk", new Color(.34f,.23f,.13f));
            var trunk = Primitive("Tree trunk", PrimitiveType.Cylinder, position + Vector3.up * 1.4f, new Vector3(.22f,1.4f,.22f), brown);
            trunk.transform.rotation = Quaternion.Euler(0,0, -15);
            for (int i = 0; i < 3; i++)
            {
                var branch = Primitive("Branch", PrimitiveType.Cylinder, position + new Vector3((i - 1) * .55f, 2 + i * .3f, 0), new Vector3(.11f,.7f,.11f), brown);
                branch.transform.rotation = Quaternion.Euler(0,0, -55 + i * 45);
                Primitive("Tree crown", PrimitiveType.Sphere, position + new Vector3((i - 1) * .75f, 2.7f + i * .3f, 0), new Vector3(1.9f,1.2f,1.3f), Mat("crown" + i, new Color(.22f+i*.035f,.38f+i*.04f,.10f)));
            }
        }

        private void WoodenShelf(Vector2 point, int salt, bool ledge)
        {
            int sign = point.x > 0 ? 1 : -1;
            var wood = Mat("planks", new Color(.43f,.29f,.16f));
            Vector3 center = new Vector3(point.x + sign * .8f, point.y - .2f, .6f);
            for (int i = 0; i < 5; i++) Box("Plank", center + new Vector3(0,0,-.8f+i*.38f), new Vector3(2.4f,.18f,.34f), wood);
            for (int i = 0; i < 2; i++)
            {
                var beam = Box("Shelf support", center + new Vector3(sign*.45f,-.70f,-.55f+i*1.1f), new Vector3(.17f,1.9f,.17f), Mat("support", new Color(.26f,.18f,.12f)));
                beam.transform.rotation = Quaternion.Euler(0,0,sign*40);
            }
            if (ledge) Ledges.Add(new Ledge(center.x-1.2f,center.x+1.2f,point.y-.1f));
        }

        public void GenerateTo(float height, bool finite)
        {
            float target = finite ? Mathf.Min(height, GameRules.SummitUnits + 8) : height;
            while (sceneryChunk * 12 < target)
            {
                float y = sceneryChunk * 12;
                int zone = GameRules.ZoneAt(y);
                var random = new System.Random(seed + sceneryChunk * 8191);
                for (int side = -1; side <= 1; side += 2)
                {
                    Rock(new Vector3(side * 8.9f, y + 5, 3.3f), new Vector3(4.2f,7.8f,3.2f), sceneryChunk*37+side+400,StoneColor(zone));
                    for (int i = 0; i < 3; i++)
                    {
                        float ry = y + i * 4f;
                        Rock(new Vector3(side * (5.8f+(float)random.NextDouble()*.5f),ry,1.9f), new Vector3(1.7f,2.9f,2.3f), sceneryChunk*71+i*11+side+1900,StoneColor(zone));
                        if (zone != 4 && zone != 3)
                            Grass(new Vector3(side*5.5f,ry+2.5f,.2f),1.4f,sceneryChunk*79+i*3+side+6300);
                    }
                    if (zone == 0 || zone == 2) Tree(new Vector3(side*5.2f,y+2.2f,.5f), sceneryChunk*3+side);
                    if (location == 1)
                    {
                        Box("City beam", new Vector3(side*5.6f,y+3,0),new Vector3(.3f,7,.4f),Mat("steel",new Color(.34f,.40f,.46f)));
                        for (int i=0;i<4;i++) Box("City window",new Vector3(side*6.2f,y+i*2.2f,-.6f),new Vector3(.55f,.9f,.1f),Mat("window",new Color(.49f,.81f,.89f),true));
                    }
                }
                // Depth, haze and clouds behind the climbing corridor.
                for (int i = 0; i < 2; i++)
                {
                    float x = -7 + (float)random.NextDouble()*14;
                    Rock(new Vector3(x,y-4,22+i*9),new Vector3(1.3f,7+(float)random.NextDouble()*9,1.6f),sceneryChunk*19+i+9200,new Color(.57f,.70f,.76f));
                    var cloud = Primitive("Cloud",PrimitiveType.Sphere,new Vector3(x,y+2,16),new Vector3(3.5f,.85f,1.2f),Mat("cloud",new Color(.91f,.95f,.98f),true));
                    CloudTransforms.Add(cloud.transform);
                }
                sceneryChunk++;
            }
            while (4.8f + mainIndex * 3.5f < target - 1)
            {
                int index = mainIndex++;
                var random = new System.Random(seed + index*1741);
                float y = 4.8f + index*3.5f + ((float)random.NextDouble()-.5f)*.28f;
                float x = (index%2==0?1:-1)*(1.9f+((float)random.NextDouble()-.5f)*.35f);
                int zone = GameRules.ZoneAt(y);
                // The main route always accepts the base grip. Advanced surfaces are optional shortcuts.
                MaterialKind kind = index > 2 && index%9==5 ? MaterialKind.Root : index%11==7 ? MaterialKind.Spring : MaterialKind.Stone;
                AddAnchor(new Vector2(x,y),kind);
                Rock(new Vector3(x + Mathf.Sign(x)*1.4f,y-.4f,1.4f),new Vector3(1.6f,.8f,1.5f),index+21000,StoneColor(zone));
                if (index%3==0) WoodenShelf(new Vector2(x,y-1.0f),index+18000,index%6==0);
                if (zone < 3) Grass(new Vector3(x + Mathf.Sign(x)*.8f,y+.3f,.4f),.8f,index+9900);
                AddLoot(new Vector2(x*.4f,y-1.8f),zone,GameRules.LootPrices[zone],false);
                if (index%4==2)
                {
                    AddLoot(new Vector2(-Mathf.Sign(x)*4.4f,y+.35f),zone,Mathf.RoundToInt(GameRules.LootPrices[zone]*1.8f),true);
                    if (zone >= 3) AddAnchor(new Vector2(-Mathf.Sign(x)*4.2f,y+1.6f),zone >= 5 ? MaterialKind.Crystal : MaterialKind.Ice);
                }
            }
            GeneratedHeight = target;
            if (finite && target >= GameRules.SummitUnits)
            {
                WoodenShelf(new Vector2(0,GameRules.SummitUnits-.5f),88000,true);
                var pole = Box("Summit flag pole",new Vector3(.4f,GameRules.SummitUnits+1,0),new Vector3(.09f,3,.09f),Mat("flagPole",new Color(.69f,.55f,.32f)));
                Box("Summit flag",pole.transform.position+new Vector3(.6f,.7f,0),new Vector3(1.1f,.7f,.06f),Mat("flag",new Color(.89f,.29f,.13f)));
            }
        }

        private void AddAnchor(Vector2 position, MaterialKind kind)
        {
            int id = anchorId++;
            var holder = new GameObject("Anchor " + id + " " + kind).transform;
            holder.SetParent(Root); holder.position = new Vector3(position.x,position.y,-.45f);
            Color glow = kind == MaterialKind.Root ? new Color(.98f,.68f,.25f) : kind == MaterialKind.Spring ? new Color(.57f,.94f,.37f) : kind == MaterialKind.Ice ? new Color(.64f,.93f,1) : kind == MaterialKind.Crystal ? new Color(.81f,.48f,1) : new Color(.19f,.81f,1);
            var rock = Primitive("Anchor mount",PrimitiveType.Sphere,holder.position+Vector3.forward*.2f,new Vector3(.72f,.7f,.43f),Mat("mount",new Color(.19f,.23f,.24f)),holder);
            var crystal = Primitive("Crystal",PrimitiveType.Cube,holder.position,new Vector3(.23f,.39f,.16f),Mat("anchorGlow"+kind,glow,true),holder);
            crystal.transform.rotation = Quaternion.Euler(12,20,35);
            var ring = holder.gameObject.AddComponent<LineRenderer>();
            ring.positionCount = 25; ring.startWidth = .045f; ring.endWidth = .045f;
            ring.sharedMaterial = Mat("ring"+kind,glow*.75f,true); ring.useWorldSpace = false;
            for (int i=0;i<25;i++) { float a=i*Mathf.PI*2/24; ring.SetPosition(i,new Vector3(Mathf.Cos(a)*.43f,Mathf.Sin(a)*.43f,-.1f)); }
            Anchors.Add(new AnchorPoint { Id=id,Position=position,Kind=kind,Visual=holder,Glow=crystal.GetComponent<Renderer>() });
        }

        private void AddLoot(Vector2 position,int tier,int value,bool rare)
        {
            var holder = new GameObject("Loot " + lootId).transform; holder.SetParent(Root); holder.position=new Vector3(position.x,position.y,-.45f);
            Color color=rare?new Color(1,.67f,.23f):new Color(1,.83f,.39f);
            var core=Primitive("Find",PrimitiveType.Cube,holder.position,new Vector3(.3f,.38f,.3f),Mat("loot"+(rare?1:0),color),holder);
            core.transform.rotation=Quaternion.Euler(20,30,35);
            Box("Find band",holder.position+Vector3.back*.16f,new Vector3(.33f,.09f,.08f),Mat("lootBand",new Color(.42f,.27f,.10f)),holder);
            Loot.Add(new WorldLoot { Item=new LootItem(lootId++,tier,value),Position=position,Visual=holder });
        }

        public AnchorPoint FindAnchor(int id) { return Anchors.Find(a => a.Id==id); }
        public void Dispose()
        {
            if (Root != null) UnityEngine.Object.Destroy(Root.gameObject);
            foreach (var material in materials.Values) UnityEngine.Object.Destroy(material);
        }
    }
}
