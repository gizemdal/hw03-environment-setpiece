#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time, u_AO, u_DayTime;

in vec2 fs_Pos;
out vec4 out_Col;

vec3 seed = vec3(0.1, 0.05, 0.49);

struct roomData {
	float walls; // walls
	float floor; // floor
	float ceiling; // ceiling
	float picture1; // picture on the wall 1
	float picture2; // picture on the wall 2
	float nightstand; // nightstand
	vec3 lamp; // lamp
	vec3 chair;
	float bedFrame; // the bed frame
	float mattress; // bed mattress
	float pillow; // pillow on the bed
	vec3 moon; // the moon outside

	vec3 finalPos;
	int objectID;
};

float power(float x, int y) {
  float ret = 1.0;
  for (int i = y; i > 0; i--) {
    ret *= x;
  }
  return ret;
}

float random (in vec2 st) {
    return fract(sin(dot(st.xy,
                         vec2(12.9898,78.233)))
                * 43758.5453123);
}

float random1( vec2 p , vec2 seed) {
  return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 random2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

vec2 random2(vec3 p) {
    return fract(sin(vec2(p.x, p.x + 1.0)) * vec2(43758.5453123, 22578.1459123));
}

float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    vec2 u = f*f*(3.0-2.0*f);
    return mix( mix( random( i + vec2(0.0,0.0) ),
                     random( i + vec2(1.0,0.0) ), u.x),
                mix( random( i + vec2(0.0,1.0) ),
                     random( i + vec2(1.0,1.0) ), u.x), u.y);
}

mat2 rotate2d(float angle){
    return mat2(cos(angle),-sin(angle),
                sin(angle),cos(angle));
}

float lines(in vec2 pos, float b){
    float scale = 10.0;
    pos *= scale;
    return smoothstep(0.0,
                    .5+b*.5,
                    abs((sin(pos.x*3.1415)+b*2.0))*.5);
}

vec3 rayCast() {
	vec2 pixelPos = vec2(gl_FragCoord);
	vec2 screenPos = vec2((pixelPos.x / u_Dimensions.x) * 2.0 - 1.0, 1.0 - (pixelPos.y / u_Dimensions.y) * 2.0);
	float length = length(u_Ref - u_Eye);
	vec3 V = -u_Up * length * tan(radians(90.0 / 2.0));
	vec3 u_Look = normalize(u_Ref - u_Eye);
	vec3 u_Right = normalize(cross(u_Look, u_Up));
	vec3 H = u_Right * length * (u_Dimensions.x / u_Dimensions.y) * tan(radians(90.0 / 2.0));
	vec3 world = u_Ref + screenPos.x * H + screenPos.y * V;
	return normalize(world - u_Eye);
}

float interpNoise2D(float x, float y) {
  float intX = floor(x);
  float fractX = fract(x);
  float intY = floor(y);
  float fractY = fract(y);

  float v1 = random1(vec2(intX, intY), seed.xy);
  float v2 = random1(vec2(intX + 1.0, intY), seed.xy);
  float v3 = random1(vec2(intX, intY + 1.0), seed.xy);
  float v4 = random1(vec2(intX + 1.0, intY + 1.0), seed.xy);

  float i1 = mix(v1, v2, fractX);
  float i2 = mix(v3, v4, fractX);
  return mix(i1, i2, fractY);
}

float fbm(float x, float y, float octaves) {
  float total = 0.0;
  float persistence = 0.5;

  for(int i = 0; i < int(ceil(octaves)); i++) {
    float freq = power(2.0, i);
    float amp = power(persistence, i);
    total += interpNoise2D(x * freq, y * freq) * amp;
  }
  return total;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 d = abs(p) - b;
  return length(max(d,0.0))
         + min(max(d.x,max(d.y,d.z)),0.0); // remove this line for an only partially signed sdf 
}

float sdPlane( vec3 p, vec4 n )
{
  // n must be normalized
  return dot(p,n.xyz) + n.w;
}

float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdRoundedCylinder( vec3 p, float ra, float rb, float h )
{
    vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
    return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

float sdVerticalCapsule( vec3 p, float h, float r )
{
    p.y -= clamp( p.y, 0.0, h );
    return length( p ) - r;
}

float sdRoundCone( in vec3 p, in float r1, float r2, float h )
{
    vec2 q = vec2( length(p.xz), p.y );
    
    float b = (r1-r2)/h;
    float a = sqrt(1.0-b*b);
    float k = dot(q,vec2(-b,a));
    
    if( k < 0.0 ) return length(q) - r1;
    if( k > a*h ) return length(q-vec2(0.0,h)) - r2;
        
    return dot(q, vec2(a,b) ) - r1;
}
	
float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 d = abs(p) - b;
  return length(max(d,0.0)) - r
         + min(max(d.x,max(d.y,d.z)),0.0); // remove this line for an only partially signed sdf 
}

float opSmoothUnion( float d1, float d2, float k ) {
	float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); 
}

float opUnion( float d1, float d2 ) {  
	return min(d1,d2); 
}

float opSubtraction( float d1, float d2 ) {
	return max(-d1,d2); 
}

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

float square_wave(float x, float freq, float amplitude) {
	return abs(float(int(floor(x * freq)) % 2) * amplitude);
}

mat4 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(1, 0, 0, 0),
        vec4(0, c, -s, 0),
        vec4(0, s, c, 0),
        vec4(0, 0, 0, 1)
    );
}

mat4 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(c, 0, s, 0),
        vec4(0, 1, 0, 0),
        vec4(-s, 0, c, 0),
        vec4(0, 0, 0, 1)
    );
}

mat4 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(c, -s, 0, 0),
        vec4(s, c, 0, 0),
        vec4(0, 0, 1, 0),
        vec4(0, 0, 0, 1)
    );
}

vec2 skew (vec2 st) {
    vec2 r = vec2(0.0);
    r.x = 1.1547*st.x;
    r.y = st.y+0.5*r.x;
    return r;
}

vec3 simplexGrid (vec2 st) {
    vec3 xyz = vec3(0.0);

    vec2 p = fract(skew(st));
    if (p.x > p.y) {
        xyz.xy = 1.0-vec2(p.x,p.y-p.x);
        xyz.z = p.y;
    } else {
        xyz.yz = 1.0-vec2(p.x-p.y,p.y);
        xyz.x = p.x;
    }

    return fract(xyz);
}

float curtainNoise(vec3 pos, float t) {
	vec3 noisePos = vec3(pos.x + sin(t * 0.1), pos.y, pos.z);
	float actual = sdBox(noisePos, vec3(0.1, 4.0, 0.5));
	//actual = sin(t * 0.01) * actual;
	return actual;
}

vec4 generateSky() {
	if (u_DayTime == 1.0) {
		return vec4(102.0 / 256.0, 204.0 / 256.0, 1.0, 1.0);
	}
    vec3 diffuseColor = vec3(0);
    float x = gl_FragCoord.x / 70.0; // scaled x coordinate of UV
    float y = gl_FragCoord.y / 50.0; // scaled y coordinate of UV
    int cellX = int(x); // lower-left X coordinate in which the point lies
    int cellY = int(y); // lower-left Y coordinate in which the point lies
    vec2 randomPoint = random2(vec2(cellX, cellY)); // random point in the cell that our point belongs to
    randomPoint += vec2(cellX, cellY); // add randomPoint with cell coordinates to make our random point fall into given cell
    vec2 closest = randomPoint; // keep track of closest random point to our current pixel
    for (int i = cellY - 1; i <= cellY + 1; i++) {
        // skip the coordinate if out of bounds
        if (i < 0 || i > int(u_Dimensions.y)) {
            continue;
        }
        for (int j = cellX - 1; j <= cellX + 1; j++) {
            // skip the coordinate if out of bounds
            if (j < 0 || j > int(u_Dimensions.x)) {
                continue;
            }
            vec2 rand = random2(vec2(j, i)); // find the random point in neighbor pixel
            rand += vec2(j, i); // add randomPoint with cell coordinates to make our random point fall into given cell
            float distance = sqrt(power(x - rand.x, 2) + power(y - rand.y, 2)); // calculate distance
            if (distance < sqrt(power(x - closest.x, 2) + power(y - closest.y, 2))) {
                closest = rand;
            }
        }
    }
    float difference = sqrt(power(x - (closest.x - 0.25), 2) + power(y - (closest.y - 0.25), 2)); // calculate the distance between pixel and closest point
    if (difference < 0.05) {
    	return vec4(1.0, 1.0, sin(u_Time * 0.1) * 204.0 / 256.0, 1.0);
    } else {
    	return vec4(vec3(0.0, 0.0, 50.0 / 256.0), 1.0);
    }
}

float sceneIntersect(vec3 currPos, out roomData rd) {

	float wallH = 6.0; // wall height
	float wallWSides = 6.0; // wall width sides
	float wallWBack = 10.0; // wall width back

	// Left wall
	vec3 leftWallPos = vec3(currPos.x - wallWBack, currPos.y, currPos.z);
	float leftWall = sdBox(leftWallPos, vec3(0.1, wallH, wallWSides));
	float leftWindow = sdBox(leftWallPos, vec3(0.2, 3.0, 3.0));
	float windowBarH = sdBox(leftWallPos, vec3(0.1, 0.2, 3.0)); // horizontal bar
	float windowBarV = sdBox(leftWallPos, vec3(0.1, 3.0, 0.2)); // vertical bar
	float barsL = opUnion(windowBarH, windowBarV);
	float curtBoxL = sdBox(vec3(leftWallPos.x, leftWallPos.y - wallH / 2.0, leftWallPos.z), vec3(0.3, 0.2, 3.2));
	float curtL = curtainNoise(leftWallPos, u_Time);
	leftWall = opSubtraction(leftWindow, leftWall);
	leftWall = opUnion(leftWall, barsL);
	leftWall = opUnion(leftWall, curtBoxL);

	// Back wall
	vec3 rotWY = (rotateY(-1.575) * vec4(currPos, 1.0)).xyz;
	vec3 backWallPos = vec3(rotWY.x - wallWSides, rotWY.y, rotWY.z);
	float backWall = sdBox(backWallPos, vec3(0.1, wallH, wallWBack));
	float pic1 = sdBox(vec3(backWallPos.x + 0.5, backWallPos.y - 3.0, backWallPos.z), vec3(0.1, 1.5, 2.0));
	float pic2 = sdBox(vec3(backWallPos.x + 0.5, backWallPos.y, backWallPos.z + 6.0), vec3(0.1, 3.0, 1.0));
	pic1 = min(pic1, pic2);
	//rd.backWall = backWall;

	// Construct the bed frame
	float headrest = sdBox(vec3(rotWY.x - 4.0, rotWY.y + 1.5, rotWY.z), vec3(0.1, 2.5, 3.0));
	float footLB = sdBox(vec3(rotWY.x - 3.0, rotWY.y + 5.5, rotWY.z + 2.0), vec3(0.3, 0.5, 0.3));
	float footLF = sdBox(vec3(rotWY.x + 3.5, rotWY.y + 5.5, rotWY.z + 2.0), vec3(0.3, 0.5, 0.3));
	float footRB = sdBox(vec3(rotWY.x - 3.0, rotWY.y + 5.5, rotWY.z - 2.0), vec3(0.3, 0.5, 0.3));
	float footRF = sdBox(vec3(rotWY.x + 3.5, rotWY.y + 5.5, rotWY.z - 2.0), vec3(0.3, 0.5, 0.3));
	headrest = min(min(min(min(headrest, footLB), footRB), footLF), footRF);
	vec3 rotWZ = (rotateZ(-1.575) * vec4(currPos, 1.0)).xyz;
	float bed = sdBox(vec3(rotWZ.x - 4.5, rotWZ.y, rotWZ.z), vec3(0.5, 3.0, 4.5));
	headrest = opSmoothUnion(headrest, bed, 0.3);
	rd.bedFrame = headrest;

	float mattress = sdRoundBox(vec3(rotWZ.x - 3.5, rotWZ.y, rotWZ.z + 0.8), vec3(0.5, 2.8, 4.3), 0.3);
	rd.mattress = mattress;

	// Construct the nightstand
	float drawer = sdBox(vec3(currPos.x + 5.0, currPos.y + 4.0, currPos.z - 3.0), vec3(1.5, 1.5, 1.3));
	rd.nightstand = drawer;

	// Construct the lamp
	vec3 lampPos = vec3(currPos.x + 5.0, currPos.y + 1.75, currPos.z - 2.8);
	float Lbody = sdSphere(lampPos, 0.8);
	float Lhead = sdRoundCone(vec3(lampPos.x, lampPos.y - 2.0, lampPos.z), 0.9, 0.4, 1.0);
	float Lconnection = sdVerticalCapsule(vec3(lampPos.x, lampPos.y - 1.0, lampPos.z), 2.0, 0.1);
	float lamp = opSmoothUnion(Lconnection, Lbody, 0.3);
	rd.lamp = vec3(lampPos.x, lampPos.y - 2.0, lampPos.z);

	// Right wall
	rotWY = (rotateY(-1.575) * vec4(rotWY, 1.0)).xyz;
	vec3 rightWallPos = vec3(rotWY.x - wallWBack, rotWY.y, rotWY.z);
	float rightWall = sdBox(rightWallPos, vec3(0.1, wallH, wallWSides));
	float rightWindow = sdBox(rightWallPos, vec3(0.2, 3.0, 3.0));
	windowBarH = sdBox(rightWallPos, vec3(0.1, 0.2, 3.0)); // horizontal bar
	windowBarV = sdBox(rightWallPos, vec3(0.1, 3.0, 0.2)); // vertical bar
	float curtBoxR = sdBox(vec3(rightWallPos.x, rightWallPos.y - wallH / 2.0, rightWallPos.z), vec3(0.3, 0.2, 3.2));
	float barsR = opUnion(windowBarH, windowBarV);
	rightWall = opSubtraction(rightWindow, rightWall);
	rightWall = opUnion(rightWall, barsR);
	rightWall = opUnion(rightWall, curtBoxR);

	// Floor & ceiling
	float floor = sdBox(vec3(rotWZ.x - wallH, rotWZ.y, rotWZ.z), vec3(0.1, wallWBack, wallWSides));
	float ceiling = sdBox(vec3(rotWZ.x + wallH, rotWZ.y, rotWZ.z), vec3(0.1, wallWBack, wallWSides));
	rd.floor = floor;
	rd.ceiling = ceiling;

	// Chair
	vec3 chairPos = vec3(currPos.x - 7.0, currPos.y + 4.0, currPos.z - 2.0);
	chairPos = (rotateY(-0.7) * vec4(chairPos, 1.0)).xyz;
	float chairBottom = sdRoundedCylinder(chairPos, 0.45, 0.15, 0.10);
	vec3 rotChairL1 =  (rotateZ(0.2) * rotateX(0.2) * vec4(chairPos, 1.0)).xyz;
	vec3 chairL1Pos = vec3(rotChairL1.x - 0.4, rotChairL1.y + 2.0, rotChairL1.z + 0.4);
	float chairL1 = sdVerticalCapsule(chairL1Pos, 1.75, 0.125);

	vec3 rotChairL2 =  (rotateZ(0.2) * rotateX(-0.2) * vec4(chairPos, 1.0)).xyz;
	vec3 chairL2Pos = vec3(rotChairL2.x - 0.4, rotChairL2.y + 2.0, rotChairL2.z - 0.4);
	float chairL2 = sdVerticalCapsule(chairL2Pos, 1.75, 0.125);
	
	vec3 rotChairR1 =  (rotateZ(-0.2) * rotateX(0.2) * vec4(chairPos, 1.0)).xyz;
	vec3 chairR1Pos = vec3(rotChairR1.x + 0.4, rotChairR1.y + 2.0, rotChairR1.z + 0.4);
	float chairR1 = sdVerticalCapsule(chairR1Pos, 1.75, 0.125);
	
	vec3 rotChairR2 =  (rotateZ(-0.2) * rotateX(-0.2) * vec4(chairPos, 1.0)).xyz;
	vec3 chairR2Pos = vec3(rotChairR2.x + 0.4, rotChairR2.y + 2.0, rotChairR2.z - 0.4);
	float chairR2 = sdVerticalCapsule(chairR2Pos, 1.75, 0.125);

	vec3 rotChairBack = (rotateZ(-0.2) * vec4(chairPos, 1.0)).xyz;
	float chairBack = sdRoundBox(vec3(rotChairBack.x - 0.5, rotChairBack.y - 1.2, rotChairBack.z), vec3(0.001, 0.7, 0.5), 0.2);
	chairL1 = opSmoothUnion(chairL1, chairL2, 0.2);
	chairR1 = opSmoothUnion(chairR1, chairR2, 0.2);
	chairL1 = opSmoothUnion(chairL1, chairR1, 0.2);

	chairBottom = opSmoothUnion(chairBottom, chairL1, 0.2);
	chairBottom = opSmoothUnion(chairBottom, chairBack, 0.2);

	// Merge the walls
	float walls = opSmoothUnion(backWall, leftWall, 0.3);
	walls = opSmoothUnion(walls, rightWall, 0.3);
	rd.walls = walls;

	rd.moon = vec3(currPos.x + cos(u_Time * 0.01) * 35.0, currPos.y + sin(u_Time * 0.01) * 35.0, currPos.z - 20.0); //- 20.0);
	float moon = sdSphere(rd.moon, 3.0);

	float minDist = min(min(min(min(min(min(min(min(min(min(walls, floor), 
		headrest), ceiling), drawer), lamp), mattress), pic1), moon), Lhead), chairBottom);
	rd.objectID = 0;
		
	if(minDist == rd.floor) {
		rd.objectID = 1;
	}
	if(minDist == rd.ceiling) {
		rd.objectID = 2;
	}
	if(minDist == rd.walls) {
		rd.objectID = 3;
	}
	if (minDist == rd.bedFrame) {
		rd.objectID = 4;
	}
	if (minDist == rd.nightstand) {
		rd.objectID = 5;
	}
	if (minDist == lamp) {
		rd.objectID = 6;
	}
	if (minDist == rd.mattress) {
		rd.objectID = 7;
	}
	if (minDist == pic1) {
		rd.objectID = 8;
	}
	if (minDist == moon) {
		rd.objectID = 9;
	} if (minDist == Lhead) {
		rd.objectID = 10;
	} if (minDist == chairBottom) {
		rd.objectID = 11;
	}
	rd.finalPos = currPos;
	return minDist;
}

float sceneMoon(vec3 currPos, out roomData rd) {

	float wallH = 6.0; // wall height
	float wallWSides = 6.0; // wall width sides
	float wallWBack = 10.0; // wall width back

	// Left wall
	vec3 leftWallPos = vec3(currPos.x - wallWBack, currPos.y, currPos.z);
	float leftWall = sdBox(leftWallPos, vec3(0.1, wallH, wallWSides));
	float leftWindow = sdBox(leftWallPos, vec3(0.2, 3.0, 3.0));
	float windowBarH = sdBox(leftWallPos, vec3(0.1, 0.2, 3.0)); // horizontal bar
	float windowBarV = sdBox(leftWallPos, vec3(0.1, 3.0, 0.2)); // vertical bar
	float barsL = opUnion(windowBarH, windowBarV);
	float curtBoxL = sdBox(vec3(leftWallPos.x, leftWallPos.y - wallH / 2.0, leftWallPos.z), vec3(0.3, 0.2, 3.2));
	float curtL = curtainNoise(leftWallPos, u_Time);
	leftWall = opSubtraction(leftWindow, leftWall);
	leftWall = opUnion(leftWall, barsL);
	leftWall = opUnion(leftWall, curtBoxL);

	// Back wall
	vec3 rotWY = (rotateY(-1.575) * vec4(currPos, 1.0)).xyz;
	vec3 backWallPos = vec3(rotWY.x - wallWSides, rotWY.y, rotWY.z);
	float backWall = sdBox(backWallPos, vec3(0.1, wallH, wallWBack));
	float pic1 = sdBox(vec3(backWallPos.x + 0.5, backWallPos.y - 3.0, backWallPos.z), vec3(0.1, 1.5, 2.0));
	float pic2 = sdBox(vec3(backWallPos.x + 0.5, backWallPos.y, backWallPos.z + 6.0), vec3(0.1, 3.0, 1.0));
	pic1 = min(pic1, pic2);
	//rd.backWall = backWall;

	// Construct the bed frame
	float headrest = sdBox(vec3(rotWY.x - 4.0, rotWY.y + 1.5, rotWY.z), vec3(0.1, 2.5, 3.0));
	float footLB = sdBox(vec3(rotWY.x - 3.0, rotWY.y + 5.5, rotWY.z + 2.0), vec3(0.3, 0.5, 0.3));
	float footLF = sdBox(vec3(rotWY.x + 3.5, rotWY.y + 5.5, rotWY.z + 2.0), vec3(0.3, 0.5, 0.3));
	float footRB = sdBox(vec3(rotWY.x - 3.0, rotWY.y + 5.5, rotWY.z - 2.0), vec3(0.3, 0.5, 0.3));
	float footRF = sdBox(vec3(rotWY.x + 3.5, rotWY.y + 5.5, rotWY.z - 2.0), vec3(0.3, 0.5, 0.3));
	headrest = min(min(min(min(headrest, footLB), footRB), footLF), footRF);
	vec3 rotWZ = (rotateZ(-1.575) * vec4(currPos, 1.0)).xyz;
	float bed = sdBox(vec3(rotWZ.x - 4.5, rotWZ.y, rotWZ.z), vec3(0.5, 3.0, 4.5));
	headrest = opSmoothUnion(headrest, bed, 0.3);
	rd.bedFrame = headrest;

	float mattress = sdRoundBox(vec3(rotWZ.x - 3.5, rotWZ.y, rotWZ.z + 0.8), vec3(0.5, 2.8, 4.3), 0.3);
	rd.mattress = mattress;

	// Construct the nightstand
	float drawer = sdBox(vec3(currPos.x + 5.0, currPos.y + 4.0, currPos.z - 3.0), vec3(1.5, 1.5, 1.3));
	rd.nightstand = drawer;

	// Construct the lamp
	vec3 lampPos = vec3(currPos.x + 5.0, currPos.y + 1.75, currPos.z - 2.8);
	float Lbody = sdSphere(lampPos, 0.8);
	float Lhead = sdRoundCone(vec3(lampPos.x, lampPos.y - 2.0, lampPos.z), 0.9, 0.4, 1.0);
	float Lconnection = sdVerticalCapsule(vec3(lampPos.x, lampPos.y - 1.0, lampPos.z), 2.0, 0.1);
	float lamp = opSmoothUnion(Lconnection, Lbody, 0.3);
	rd.lamp = vec3(lampPos.x, lampPos.y - 2.0, lampPos.z);

	// Right wall
	rotWY = (rotateY(-1.575) * vec4(rotWY, 1.0)).xyz;
	vec3 rightWallPos = vec3(rotWY.x - wallWBack, rotWY.y, rotWY.z);
	float rightWall = sdBox(rightWallPos, vec3(0.1, wallH, wallWSides));
	float rightWindow = sdBox(rightWallPos, vec3(0.2, 3.0, 3.0));
	windowBarH = sdBox(rightWallPos, vec3(0.1, 0.2, 3.0)); // horizontal bar
	windowBarV = sdBox(rightWallPos, vec3(0.1, 3.0, 0.2)); // vertical bar
	float curtBoxR = sdBox(vec3(rightWallPos.x, rightWallPos.y - wallH / 2.0, rightWallPos.z), vec3(0.3, 0.2, 3.2));
	float barsR = opUnion(windowBarH, windowBarV);
	rightWall = opSubtraction(rightWindow, rightWall);
	rightWall = opUnion(rightWall, barsR);
	rightWall = opUnion(rightWall, curtBoxR);

	// Floor & ceiling
	float floor = sdBox(vec3(rotWZ.x - wallH, rotWZ.y, rotWZ.z), vec3(0.1, wallWBack, wallWSides));
	float ceiling = sdBox(vec3(rotWZ.x + wallH, rotWZ.y, rotWZ.z), vec3(0.1, wallWBack, wallWSides));
	rd.floor = floor;
	rd.ceiling = ceiling;

	// Merge the walls
	float walls = opSmoothUnion(backWall, leftWall, 0.3);
	walls = opSmoothUnion(walls, rightWall, 0.3);
	rd.walls = walls;

	float minDist = min(min(min(min(min(min(min(min(walls, floor), headrest), ceiling), drawer), lamp), mattress), pic1), Lhead);
	rd.finalPos = currPos;
	return minDist;
}

vec3 computeNormal(vec3 p) {
	roomData rd;
	float xl = sceneIntersect(p + vec3(-0.001, 0.0, 0.0), rd);
	float xh = sceneIntersect(p + vec3(0.001, 0.0, 0.0), rd);

	float yl = sceneIntersect(p + vec3(0.0, -0.001, 0.0), rd);
	float yh = sceneIntersect(p + vec3(0.0, 0.001, 0.0), rd);

	float zl = sceneIntersect(p + vec3(0.0, 0.0, -0.001), rd);
	float zh = sceneIntersect(p + vec3(0.0, 0.0, 0.001), rd);

	return normalize(vec3(xh - xl, yh - yl, zh - zl));
}

float softShadow(vec3 dir, vec3 origin, float min_t, float max_t, float k) {
	roomData rd;
	float res = 1.0;
	for (float t = min_t; t < max_t;) {
		float m = sceneIntersect(origin + t * dir, rd);
		if (m < 0.001) {
			return 0.0; // in shadow
		}
		res = min(res, k * m / t);
		t += m;
	}
	return res;
}

float moonShadow(vec3 dir, vec3 origin, float min_t, float max_t, float k) {
	roomData rd;
	float res = 1.0;
	for (float t = min_t; t < max_t;) {
		float m = sceneMoon(origin + t * dir, rd);
		if (m < 0.001) {
			return 0.0; // in shadow
		}
		res = min(res, k * m / t);
		t += m;
	}
	return res;
}

void coordinateSystem(const vec3 v1, out vec3 v2, out vec3 v3) {
    
    if (abs(v1.x) > abs(v1.y)) {
        v2 = vec3(-v1.z, 0, v1.x) / length(v1.xz);
    }
    else {
        v2 = vec3(0, v1.z, -v1.y) / length(v1.yz);
    }
    v3 = cross(v1, v2);
}

float computeAO(vec3 p, vec3 n, float dist) {
    float aoSum = 0.0;
    roomData rd;
    // Sample a few points in the hemisphere around n at p
    vec3 t, b;
    // Make a tangent and bitangent vector
    coordinateSystem(n, t, b);
    for(int i = 0; i < 250; ++i) {
        // Generate a pair of random [0, 1] floats
        vec2 xi = random2(p + float(i) * 203.1);
        // Convert the xi pair to a vector in the hemisphere
        float len = sqrt(xi.y);
        float rx = len * cos(6.2831 * xi.x);
        float ry = len * sin(6.2831 * xi.x);
        float rz = sqrt(1.0 - xi.y); // z = sqrt(1 - x*x - y*y)
        vec3 dir = vec3(rx * t + ry * b + rz * n);
        aoSum += step(0.0, sceneIntersect(p + dir * dist , rd));
    }
    return aoSum / float(256);
}

void main() {
	vec3 rayDir = rayCast();
	roomData rd;
	bool hitAThing = false;
	float t = 0.001;

	for(int i = 0; i < 45; ++i) {
		float dist = sceneIntersect(u_Eye + t * rayDir, rd);
		if(dist > 0.01) {
			t += dist;
		}
		else {
			hitAThing = true;
			break;
		}
	}

	vec3 pos = u_Eye + t * rayDir;
	vec3 surfaceNormal = computeNormal(pos);
	vec3 keyLight = vec3(4.0, 5.0, -10.0);
	vec3 fillLight = vec3(-4.0, 5.0, -10.0);

	vec3 fs_LightVec1 = normalize(-rd.moon - pos);
	vec3 fs_LightVec2 = normalize(keyLight - pos);
	vec3 fs_LightVec3 = normalize(fillLight - pos);
	float diffuseTerm1 = dot(normalize(surfaceNormal.xyz), normalize(fs_LightVec1));
	float diffuseTerm2 = dot(normalize(surfaceNormal.xyz), normalize(fs_LightVec2));
	float diffuseTerm3 = dot(normalize(surfaceNormal.xyz), normalize(fs_LightVec3));
    diffuseTerm1 = clamp(diffuseTerm1, 0.0, 1.0);
    diffuseTerm2 = clamp(diffuseTerm2, 0.0, 1.0);
    diffuseTerm3 = clamp(diffuseTerm3, 0.0, 1.0);
    float ambientTerm1 = 0.15;
    float ambientTerm2 = 0.6;
    float ambientTerm3 = 0.3;
    if (u_DayTime == 1.0) {
    	ambientTerm1 = 0.6;
    	ambientTerm2 = 0.15;
    	ambientTerm3 = 0.15;
    }
    float specularIntensity1 = max(pow(dot(normalize(fs_LightVec1), normalize(surfaceNormal.xyz)), 30.0), 0.0);
    float specularIntensity2 = max(pow(dot(normalize(fs_LightVec2), normalize(surfaceNormal.xyz)), 30.0), 0.0);
    float specularIntensity3 = max(pow(dot(normalize(fs_LightVec3), normalize(surfaceNormal.xyz)), 30.0), 0.0);
    float specularIntensity = (specularIntensity1 + specularIntensity2 + specularIntensity3) / 3.0;
    float lightIntensity1 = diffuseTerm1 + ambientTerm1;
    float lightIntensity2 = diffuseTerm2 + ambientTerm2;
    float lightIntensity3 = diffuseTerm3 + ambientTerm3;
    float lightIntensity = (lightIntensity1 + lightIntensity2 + lightIntensity3) / 3.0;

	if(hitAThing) {
		if (rd.objectID == 1) {
			out_Col = vec4(0.4 * fbm(abs(gl_FragCoord.x), abs(gl_FragCoord.y), 2.0), 0.15, 0.4 * fbm(abs(gl_FragCoord.x), abs(gl_FragCoord.y), 6.0), 1.0);
		} else if (rd.objectID == 2) {
			out_Col = vec4(0.0, 0.0, 0.0, 1.0);
		} else if (rd.objectID == 3) {
			float c = square_wave(gl_FragCoord.x, 0.8, 0.5);
			out_Col = vec4(vec3(215.0/ 256.0 * c, 175.0/ 256.0 * c, 224.0/ 256.0 * c), 1.0);
		} else if (rd.objectID == 4 || rd.objectID == 11) {
			vec2 st = gl_FragCoord.xy / u_Dimensions.xy;
			st.y *= u_Dimensions.y / u_Dimensions.x;
			vec2 pos = st.yx * vec2(20., 20.);
			float pattern = pos.x;
			pos = rotate2d(noise(pos)) * pos;
			pattern = lines(pos, .5);
			out_Col = vec4(vec3(133.0/ 256.0 * pattern, 94.0/ 256.0 * pattern, 66.0/ 256.0 * pattern), 1.0);
		} else if (rd.objectID == 5) {
			out_Col = vec4(0.0, 0.0, 1.0, 1.0);
		} else if (rd.objectID == 6) {
			out_Col = vec4(0.7, 0.7, 0.7, 1.0);
		} else if (rd.objectID == 7) {
			vec2 st = gl_FragCoord.xy/u_Dimensions.xy;
    		vec3 color = vec3(0.0);
    		st *= 100.;
    		color.rb = fract(st);
    		out_Col = vec4(color,1.0);
		} else if (rd.objectID == 8) {
			vec2 pos = fs_Pos.yx * vec2(5.,7.);
    		float pattern = pos.x;
    		pos = rotate2d(noise(pos)) * pos;
    		pattern = lines(pos, .2);
    		out_Col = vec4(vec3(0.0, 0.5 * pattern, 0.7 * pattern), 1.0);
		} else if (rd.objectID == 9) {
			if (u_DayTime == 1.0) {
				out_Col = vec4(1.0, 1.0, 0.0, 1.0);
			} else {
				out_Col = vec4(vec3(0.8 * fbm(abs(gl_FragCoord.x), abs(gl_FragCoord.y), 2.0)), 1.0);
			}
		} else if (rd.objectID == 10) {
			out_Col = vec4(1.0, 0.7, 1.0, 1.0);
		}
		vec3 shadow1 = vec3(moonShadow(fs_LightVec1, pos, 0.1, 0.4, 3.0));
		vec3 shadow2 = vec3(softShadow(fs_LightVec2, pos, 0.1, 0.4, 3.0));
		vec3 shadow3 = vec3(softShadow(fs_LightVec3, pos, 0.1, 0.4, 3.0));
		vec4 coloredShadow1 = vec4(out_Col.xyz * shadow1, 1.0);
		vec4 coloredShadow2 = vec4(out_Col.xyz * shadow2, 1.0);
		vec4 coloredShadow3 = vec4(out_Col.xyz * shadow3, 1.0);
		vec4 coloredShadow = (coloredShadow1 + coloredShadow2 + coloredShadow3) / 3.0;
		out_Col = vec4(out_Col.xyz * lightIntensity + specularIntensity, 1.0) * coloredShadow;
		if (u_AO > 0.0) {
			float ao = computeAO(pos, surfaceNormal, 0.2);
			out_Col *= ao;
		}
	}
	else {
		out_Col = generateSky();
	}
	if (u_AO == 0.0) {
		// vignette effect
		float distanceX = abs(gl_FragCoord.x / u_Dimensions.x - 0.5); // x-distance
    	float distanceY = abs(gl_FragCoord.y / u_Dimensions.y - 0.5); // y-distance
    	float distanceTotal = sqrt(distanceX * distanceX + distanceY * distanceY); // distance from screen center
    	float actualDistance = distanceTotal - 0.3; // subtract the ellipse radius
    	if (actualDistance > 0.0) {
        	out_Col = vec4(vec3(clamp(out_Col.r - actualDistance, 0.0, out_Col.r), 
        	clamp(out_Col.g - actualDistance, 0.0, out_Col.g), 
        	clamp(out_Col.b - actualDistance, 0.0, out_Col.b)), 1.0);
    	}
	}
}
