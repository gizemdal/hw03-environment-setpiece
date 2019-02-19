#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

vec3 seed = vec3(0.1, 0.05, 0.49);

struct roomData {
	bool isWall; // did we hit a wall?
	bool isFloor; // did we hit the floor?
	bool isCeiling; // did the hit the ceiling?
	bool isBed; // did we hit the bed?
	bool isNightStand; // did we hit the nightstand?
	bool isLamp; // did we hit the lamp?
	bool isCurtain; // did we hit a curtain?
	bool isMoon; // did we hit the moon?
	float walls; // walls
	float floor; // floor
	float ceiling; // ceiling
	float carpet; // carpet
	float picture1; // picture on the wall 1
	float picture2; // picture on the wall 2
	float leftCurtain; // left curtain
	float rightCurtain; // right curtain
	float nightstand; // nightstand
	float lamp; // lamp
	float bedFrame; // the bed frame
	float mattress; // bed mattress
	float pillow; // pillow on the bed
	float moon; // the moon outside
	vec3 center;

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

float random1( vec2 p , vec2 seed) {
  return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
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

float opSmoothUnion( float d1, float d2, float k ) {
	float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); 
}

float opSubtraction( float d1, float d2 ) {
	return max(-d1,d2); 
}

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
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

float sceneIntersect(vec3 currPos, out roomData rd) {

	// Left wall
	vec3 leftWallPos = vec3(currPos.x - 9.0, currPos.y, currPos.z);
	float leftWall = sdBox(leftWallPos, vec3(0.1, 6.0, 5.0));
	float leftWindow = sdBox(leftWallPos, vec3(0.2, 3.0, 3.0));
	//float result = opSubtraction(leftWall, leftWindow);
	leftWall = opSubtraction(leftWindow, leftWall);

	// Back wall
	vec3 rotWY = (rotateY(-1.575) * vec4(currPos, 1.0)).xyz;
	float backWall = sdBox(vec3(rotWY.x - 5.0, rotWY.y, rotWY.z), vec3(0.1, 6.0, 9.0));
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

	// Construct the nightstand

	float drawer = sdBox(vec3(currPos.x + 5.0, currPos.y + 4.0, currPos.z - 3.0), vec3(1.5, 1.5, 1.3));
	rd.nightstand = drawer;

	// Construct the lamp
	vec3 lampPos = vec3(currPos.x + 5.0, currPos.y + 1.75, currPos.z - 3.0);
	float Lbody = sdSphere(lampPos, 0.8);
	float Lhead = sdRoundCone(vec3(lampPos.x, lampPos.y - 2.0, lampPos.z), 0.9, 0.4, 1.0);
	float Lconnection = sdVerticalCapsule(vec3(lampPos.x, lampPos.y - 1.0, lampPos.z), 2.0, 0.1);
	float lamp = min(opSmoothUnion(Lconnection, Lbody, 0.3), Lhead);
	rd.lamp = lamp;


	// Right wall
	rotWY = (rotateY(-1.575) * vec4(rotWY, 1.0)).xyz;
	vec3 rightWallPos = vec3(rotWY.x - 9.0, rotWY.y, rotWY.z);
	float rightWall = sdBox(rightWallPos, vec3(0.1, 6.0, 5.0));
	float rightWindow = sdBox(rightWallPos, vec3(0.2, 3.0, 3.0));
	//float result = opSubtraction(leftWall, leftWindow);
	rightWall = opSubtraction(rightWindow, rightWall);
	//rd.rightWall = rightWall;

	// Floor & ceiling
	float floor = sdBox(vec3(rotWZ.x - 6.0, rotWZ.y, rotWZ.z), vec3(0.1, 9.0, 5.0));
	float ceiling = sdBox(vec3(rotWZ.x + 6.0, rotWZ.y, rotWZ.z), vec3(0.1, 9.0, 5.0));
	rd.floor = floor;
	rd.ceiling = ceiling;

	// Merge the walls
	float walls = opSmoothUnion(backWall, leftWall, 0.3);
	walls = opSmoothUnion(walls, rightWall, 0.3);
	rd.walls = walls;
	//float wall = sdPlane(currPos, normalize(vec4(0.2, 0.0, 0.0, 1.0)));
	//float minDist = min(min(leftWall, backWall), rightWall);
	float minDist = min(min(min(min(min(walls, floor), ceiling), headrest), drawer), lamp);
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
	if (minDist == rd.lamp) {
		rd.objectID = 6;
	}
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
	
	vec3 fs_LightVec = normalize(u_Eye - pos);
	float diffuseTerm = dot(normalize(surfaceNormal.xyz), normalize(fs_LightVec));
    diffuseTerm = clamp(diffuseTerm, 0.0, 1.0);
    float ambientTerm = 0.05;
    float specularIntensity = max(pow(dot(normalize(fs_LightVec), normalize(surfaceNormal.xyz)), 30.0), 0.0);
    float lightIntensity = diffuseTerm + ambientTerm; 

	if(hitAThing) {
		if (rd.objectID == 1) {
			out_Col = vec4(0.0, 0.0, 0.0, 1.0);
		} else if (rd.objectID == 2) {
			out_Col = vec4(1.0, 1.0, 1.0, 1.0);
		} else if (rd.objectID == 3) {
			out_Col = vec4(0.4 * fbm(abs(fs_Pos.x), abs(fs_Pos.y), 6.0), 0.15, 0.8 * fbm(abs(fs_Pos.x), abs(fs_Pos.y), 8.0), 1.0);
		} else if (rd.objectID == 4) {
			out_Col = vec4(0.0, 1.0, 0.0, 1.0);
		} else if (rd.objectID == 5) {
			out_Col = vec4(0.0, 0.0, 1.0, 1.0);
		} else if (rd.objectID == 6) {
			out_Col = vec4(1.0, 0.0, 0.0, 1.0);
		}
		//out_Col = vec4(out_Col * lightIntensity + specularIntensity);
	}
	else {
		out_Col = vec4(0.5 * (rayDir + vec3(1.0, 1.0, 1.0)), 1.0);
	}

	
  	//out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
