import processing.video.*;
import ddf.minim.*;

class Grid {
  int x, y;
  Grid(int x, int y) { this.x = x; this.y = y; }
}
Grid[][] intersection;
PImage warpedImage;
PVector[] points = new PVector[4];
int setupProgress = 0;
boolean hasCalculated = false;

Minim minim;
AudioPlayer ballBGM;
AudioSample hitSE;

Capture cam;
Cannonball cannonball;
ArrayList<PVector> motionPoints = new ArrayList<PVector>();

ArrayList<Block> blocks = new ArrayList<Block>();

final int PIXEL_SKIP = 20; 
final int BRIGHTNESS_THRESHOLD = 170;
final int MAX_POINTS_PER_FRAME = 4000;
final float GRAVITY = 0.2;

final float CANNONBALL_BOUNCE = 1.0; 
final float BOUNCE_WALLS = 0.6;

void setup() {
  fullScreen();

  minim = new Minim(this);

  ballBGM = minim.loadFile("ball.mp3");
  hitSE = minim.loadSample("hit.mp3");
  
  String[] cameras = Capture.list();
  if (cameras.length == 0) { exit(); }
  print(Capture.list());
  cam = new Capture(this, 640, 480,Capture.list()[0]);
  cam.start();

  cannonball = new Cannonball();
  intersection = new Grid[height][width];
  warpedImage = createImage(width, height, RGB);

  int cols = 10;
  int rows = 5;
  float padding = 4;
  float blockWidth = (width - (padding * (cols + 1))) / (float)cols;
  float blockHeight = 30;
  float yOffset = 60;

  for (int j = 0; j < rows; j++) {
    for (int i = 0; i < cols; i++) {
      float x = padding + i * (blockWidth + padding);
      float y = yOffset + j * (blockHeight + padding);
      blocks.add(new Block(x, y, blockWidth, blockHeight));
    }
  }

  ballBGM.loop();
}

void draw() {
  if (cam.available()) {
    cam.read();
  }
  if (hasCalculated) {
    runMainInteraction();
  } else {
    runCalibration();
  }
}

void mousePressed() {
  if (hasCalculated) {
    setupProgress = 0;
    hasCalculated = false;
    ballBGM.pause();
    return;
  }
  if (setupProgress < 4) {
    points[setupProgress] = new PVector(mouseX, mouseY);
    setupProgress++;
    if (setupProgress >= 4) {
      thread("calculateIntersections");
    }
  }
}

void runMainInteraction() {
  renderWarpedImage();
  detectDarkPoints();

  background(255);
  
  boolean allBlocksGone = true; 
  for (Block b : blocks) {
    b.display();
    if (b.isAlive) { 
      allBlocksGone = false; 
    }
  }

  if (allBlocksGone) {
    for (Block b : blocks) {
      b.isAlive = true;
    }
  }

  int subSteps = 5;
  float dt = 1.0 / (float)subSteps;

  for (int i = 0; i < subSteps; i++) {
    cannonball.updatePhysics(dt);

    cannonball.checkBlockCollision(blocks);

    cannonball.checkCollision(motionPoints);
  }

  if (cannonball.pos.y > height + cannonball.r) { 
    cannonball.reset(); 
  }

  if (cannonball.collisionCooldown > 0) { 
    cannonball.collisionCooldown--; 
  }

  cannonball.display();
}

void runCalibration() {
  pushMatrix();
  scale(-1, 1);
  translate(-width, 0);
  image(cam, 0, 0, width, height);
  popMatrix();
  
  drawClickedPoints();
}

void detectDarkPoints() {
  warpedImage.loadPixels();
  motionPoints.clear();
  for (int i = 0; i < warpedImage.pixels.length; i += PIXEL_SKIP) { 
    if (motionPoints.size() >= MAX_POINTS_PER_FRAME) break;
    if (brightness(warpedImage.pixels[i]) < BRIGHTNESS_THRESHOLD) {
      motionPoints.add(new PVector(i % width, i / width));
    }
  }
}

void calculateIntersections() {
  hasCalculated = false;
  PVector p1 = points[1], p2 = points[0], p3 = points[3], p4 = points[2];
  PVector camP1 = screenToCamera(p1), camP2 = screenToCamera(p2), camP3 = screenToCamera(p3), camP4 = screenToCamera(p4);
  for (int j = 0; j < height; j++) {
    float v = (float)j / (height - 1);
    PVector leftPoint = PVector.lerp(camP1, camP4, v);
    PVector rightPoint = PVector.lerp(camP2, camP3, v);
    for (int i = 0; i < width; i++) {
      float u = (float)i / (width - 1);
      PVector finalPoint = PVector.lerp(leftPoint, rightPoint, u);
      intersection[j][i] = new Grid(int(finalPoint.x), int(finalPoint.y));
    }
  }
  hasCalculated = true;
}

void renderWarpedImage() {
  cam.loadPixels();
  warpedImage.loadPixels();
  for (int j = 0; j < height; j++) {
    for (int i = 0; i < width; i++) {
      Grid c = intersection[j][i];
      int flippedX = cam.width - 1 - c.x;
      if (flippedX >= 0 && flippedX < cam.width && c.y >= 0 && c.y < cam.height) {
        warpedImage.pixels[j * width + i] = cam.pixels[c.y * cam.width + flippedX];
      } else {
        warpedImage.pixels[j * width + i] = color(0);
      }
    }
  }
  warpedImage.updatePixels();
}

PVector screenToCamera(PVector screenPos) {
    return new PVector(map(screenPos.x, 0, width, 0, cam.width), map(screenPos.y, 0, height, 0, cam.height));
}

void drawClickedPoints() {
  strokeWeight(10);
  stroke(255,0,0);
  line(0,0,0,height-1);
  line(0,height-1,width-1,height-1);
  line(width-1,0,width-1,height-1); 
  line(0,0,width-1,0); 
  fill(255, 0, 0);
  noStroke();
  for (int i = 0; i < setupProgress; i++) {
    circle(points[i].x, points[i].y, 10);
  }
}

class Block {
  float x, y, w, h;
  boolean isAlive;
  color c;

  Block(float x, float y, float w, float h) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.isAlive = true;
    this.c = color(random(50, 200), random(50, 200), random(50, 200), 200);
  }

  void display() {
    if (isAlive) {
      fill(c);
      stroke(255);
      strokeWeight(2);
      rect(x, y, w, h);
    }
  }
}

class Cannonball { 
  PVector pos, vel; 
  float r; 
  color c; 
  int collisionCooldown; 
  Cannonball() { 
    r = 60; 
    reset(); 
    c = color(random(150, 255), random(150, 255), random(150, 255), 230); 
  } 
  
  void updatePhysics(float dt) { 
    vel.y += GRAVITY * dt; 
    pos.add(PVector.mult(vel, dt)); 

    if (pos.x < r || pos.x > width - r) { 
      vel.x *= -BOUNCE_WALLS; 
      pos.x = constrain(pos.x, r, width - r); 
      c = color(random(150, 255), random(150, 255), random(150, 255), 230);
    } 
    if (pos.y < r) { 
      vel.y *= -BOUNCE_WALLS; 
      pos.y = r; 
      c = color(random(150, 255), random(150, 255), random(150, 255), 230);
    } 
  } 
  
  void display() { 
    if (collisionCooldown > 0) { 
      fill(#C4BFFF); 
    } else { 
      fill(c); 
    } 
    noStroke(); 
    circle(pos.x, pos.y, r * 2); 
  } 
  
  void reset() { 
    pos = new PVector(width / 2, height / 2); 
    vel = new PVector(random(-5, 5), random(-5, 0)); 
    collisionCooldown = 0; 
  } 

  void checkBlockCollision(ArrayList<Block> blocks) {
    for (Block b : blocks) {
      if (!b.isAlive) continue; 

      float testX = constrain(pos.x, b.x, b.x + b.w);
      float testY = constrain(pos.y, b.y, b.y + b.h);
      float distX = pos.x - testX;
      float distY = pos.y - testY;
      float distance = sqrt(distX * distX + distY * distY);

      if (distance < r) {
        b.isAlive = false; 
        hitSE.trigger();   

        PVector normal = new PVector(distX, distY);
        if (normal.mag() == 0) {
           normal = vel.copy().mult(-1);
        }
        normal.normalize();

        float dot = vel.dot(normal);
        PVector reflection = PVector.mult(normal, 2 * dot);
        vel.sub(reflection);
        vel.mult(CANNONBALL_BOUNCE); 

        float penetration = r - distance;
        pos.add(PVector.mult(normal, penetration));
      }
    }
  }

  void checkCollision(ArrayList<PVector> points) { 
    if (collisionCooldown > 0) return; 

    float pointRadius = 60; 
    ArrayList<PVector> collidingPoints = new ArrayList<PVector>(); 

    for (PVector p : points) { 
      if (dist(pos.x, pos.y, p.x, p.y) < r + pointRadius) { 
        collidingPoints.add(p); 
      } 
    } 

    if (collidingPoints.size() > 0) { 
      hitSE.trigger(); 
      
      PVector averagePos = new PVector(0, 0); 
      for (PVector p : collidingPoints) { 
        averagePos.add(p); 
      } 
      averagePos.div(collidingPoints.size()); 

      PVector repulsion = PVector.sub(pos, averagePos);
      repulsion.normalize(); 

      float repulsionStrength = 20; 
      repulsion.mult(repulsionStrength);

      vel.add(repulsion);

      float distance = dist(pos.x, pos.y, averagePos.x, averagePos.y);
      if (distance < r + pointRadius) {
        PVector correction = PVector.sub(pos, averagePos);
        correction.normalize();
        correction.mult((r + pointRadius) - distance);
        pos.add(correction);
      }
      
      collisionCooldown = 5; 
    } 
  } 
}

void stop() {
  ballBGM.close();
  minim.stop();
  super.stop();
}
