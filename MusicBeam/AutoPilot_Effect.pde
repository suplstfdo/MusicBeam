/**
 * AutoPilot is a self-driving effect meant to run unattended for a whole
 * party. It listens to the music and picks a matching animation by itself:
 *
 *   - fast, driving beats (>= ~125 BPM)  -> techno style laser beam patterns
 *   - mid tempo, rhythmic music          -> slow rings, bouncing and bursting beams
 *   - calm music without a steady beat   -> softly drifting light orbs
 *   - no music at all                    -> nothing, the stage stays black
 *
 * Tuned for a real beamer without much smoke: few, large, slow moving light
 * surfaces at full brightness beat many small fast dots. Everything is drawn
 * as big blobs and wide strokes at maximum brightness; only fade-outs
 * (rings, bursts, silence) are allowed to dim.
 *
 * The tempo is estimated from the intervals between detected kicks. On every
 * musical phrase (a configurable number of beats) the effect rerolls its own
 * variation: which pattern to show, beam count, speeds and hue, so the show
 * keeps changing without any user interaction. In the fast mode one of the
 * patterns is an inverse strobe: the whole screen stays lit and only drops
 * out for a short blackout on every bass kick.
 */
class AutoPilot_Effect extends Effect
{
  Slider intensitySlider, phraseSlider, hueSlider;

  Toggle aHueToggle, bwToggle;

  static final int MODE_FLOW = 0, MODE_PULSE = 1, MODE_LASER = 2;

  static final int MAX_BEAMS = 5;

  // beat analysis
  LinkedList<Integer> kickTimes = new LinkedList<Integer>();
  float bpm = 0;
  int lastBeatMillis = -10000;
  int lastAudibleMillis = -10000;
  boolean kickNow, snareNow, hatNow;
  float kickPulse = 0, snarePulse = 0;
  float smoothLevel = 0;
  int beatsInPhrase = 0;

  int mode = MODE_FLOW;
  int candidateMode = MODE_FLOW;
  int candidateSince = 0;

  // per phrase variation
  int beamCount = 4;
  int laserPattern = 0, pulsePattern = 0, flowPattern = 0;
  boolean rowVertical = false;
  int spinDir = 1;
  float sweepSpeed = 1, sweepPhase = 0, flowPhase = 0;
  boolean ringsFromCenter = true;
  float[][] orbs = new float[5][6];
  float[][] segs = new float[4][6];       // freqX, phaseX, freqY, phaseY, rotSpeed, rotPhase
  float[][] stars = new float[6][4];      // x frac, y frac, breathe freq, breathe phase
  float[][] chase = new float[MAX_BEAMS][4]; // x, y, targetX, targetY (fractions of stage size)
  float[][] bounce = new float[MAX_BEAMS][2]; // y position, y velocity

  // laser mode state
  ArrayList<float[]> rain = new ArrayList<float[]>();   // x, y (fractions), fall speed
  float waveFreq = 0.8;
  float matrixPos = 0, matrixTarget = 0;
  int strobeDropUntil = -1;

  // rhythmic mode state
  ArrayList<float[]> rings = new ArrayList<float[]>();  // radius, x, y, hue offset
  ArrayList<float[]> sparks = new ArrayList<float[]>(); // x, y, life
  ArrayList<float[]> bursts = new ArrayList<float[]>(); // x, y, vx, vy, life
  int lastRingMillis = -10000;
  float orbitAngle = 0, orbitTarget = 0;

  AutoPilot_Effect(MusicBeam controller, int y)
  {
    super(controller, y);

    intensitySlider = cp5.addSlider("intensity"+getName()).setPosition(0, 5).setSize(395, 45).setRange(10, 100).setGroup(controlGroup);
    intensitySlider.getCaptionLabel().set("Brightness").align(ControlP5.RIGHT, ControlP5.CENTER);
    intensitySlider.setValue(100);

    phraseSlider = cp5.addSlider("phrase"+getName()).setPosition(0, 55).setSize(395, 45).setRange(8, 64).setGroup(controlGroup);
    phraseSlider.getCaptionLabel().set("Variation every (beats)").align(ControlP5.RIGHT, ControlP5.CENTER);
    phraseSlider.setValue(32);

    hueSlider = cp5.addSlider("hue"+getName()).setRange(0, 360).setSize(295, 45).setPosition(50, 105).setGroup(controlGroup);
    hueSlider.getCaptionLabel().set("hue").align(ControlP5.RIGHT, ControlP5.CENTER);
    hueSlider.setValue(200);
    HueControlListener hL = new HueControlListener();
    hueSlider.addListener(hL);

    aHueToggle = cp5.addToggle("ahue"+getName()).setPosition(0, 105).setSize(45, 45).setGroup(controlGroup);
    aHueToggle.getCaptionLabel().set("A").align(ControlP5.CENTER, ControlP5.CENTER);
    aHueToggle.setState(true);

    bwToggle = ctrl.cp5.addToggle("bw"+getName()).setPosition(350, 105).setSize(45, 45).setGroup(controlGroup);
    bwToggle.getCaptionLabel().set("BW").align(ControlP5.CENTER, ControlP5.CENTER);
    bwToggle.setState(false);

    nextVariation();
  }

  public String getName()
  {
    return "AutoPilot";
  }

  char triggeredByKey() {
    return 'b';
  }

  void draw()
  {
    float dt = 1.0/max(frameRate, 10);
    int now = ctrl.millis();

    updateAnalysis(now, dt);

    // no music -> show nothing at all
    float fade = silenceFade(now);
    if (fade <= 0) {
      rings.clear();
      sparks.clear();
      bursts.clear();
      rain.clear();
      kickPulse = snarePulse = 0;
      return;
    }

    float bright = intensitySlider.getValue() * fade;

    switch (mode) {
    case MODE_LASER:
      drawLaser(dt, bright);
      break;
    case MODE_PULSE:
      drawPulse(now, dt, bright);
      break;
    default:
      drawFlow(dt, bright);
    }
  }

  void updateAnalysis(int now, float dt)
  {
    float threshold = max(ctrl.minLevelSlider.getValue(), 0.01);
    float level = getLevel();
    smoothLevel += (level - smoothLevel) * (level > smoothLevel ? 0.3 : 0.05);
    if (level > threshold || effect_manual_triggered)
      lastAudibleMillis = now;

    kickNow = isKick() || (effect_manual_triggered && now - lastBeatMillis > 250);
    snareNow = isSnare();
    hatNow = isHat();

    if (kickNow)
      onBeat(now);
    if (snareNow)
      snarePulse = 1;

    kickPulse = max(0, kickPulse - dt*2.5);
    snarePulse = max(0, snarePulse - dt*3);

    updateBpm(now);
    updateMode(now);
  }

  void onBeat(int now)
  {
    kickPulse = 1;
    lastBeatMillis = now;
    kickTimes.add(now);
    while (kickTimes.size() > 12)
      kickTimes.removeFirst();

    if (aHueToggle.getState())
      hueSlider.setValue((hueSlider.getValue()+2)%360);

    beatsInPhrase++;
    if (beatsInPhrase >= int(phraseSlider.getValue())) {
      beatsInPhrase = 0;
      nextVariation();
      if (aHueToggle.getState())
        hueSlider.setValue((hueSlider.getValue()+47)%360);
    }
  }

  /**
   * Estimates the tempo from the median interval between recent kicks.
   * If no kick arrived for a while the estimate is dropped, which sends
   * the effect back into the calm flow mode.
   */
  void updateBpm(int now)
  {
    if (kickTimes.isEmpty())
      return;
    if (now - kickTimes.getLast() > 3000) {
      bpm = 0;
      kickTimes.clear();
      return;
    }
    ArrayList<Integer> intervals = new ArrayList<Integer>();
    for (int i = 1; i < kickTimes.size(); i++) {
      int d = kickTimes.get(i) - kickTimes.get(i-1);
      if (d >= 240 && d <= 1500)
        intervals.add(d);
    }
    if (intervals.size() < 3)
      return;
    java.util.Collections.sort(intervals);
    bpm = 60000.0 / intervals.get(intervals.size()/2);
  }

  /**
   * Picks the animation that matches the music. A new mode has to stay
   * stable for a moment before we switch, so a single odd beat does not
   * make the show jump around.
   */
  void updateMode(int now)
  {
    boolean beatAlive = !kickTimes.isEmpty() && now - kickTimes.getLast() < 2500;
    int target;
    if (beatAlive && bpm >= 125)
      target = MODE_LASER;
    else if (beatAlive && bpm >= 60)
      target = MODE_PULSE;
    else
      target = MODE_FLOW;

    if (target != candidateMode) {
      candidateMode = target;
      candidateSince = now;
    }
    if (candidateMode != mode && now - candidateSince > 1800) {
      mode = candidateMode;
      rings.clear();
      sparks.clear();
      bursts.clear();
      rain.clear();
      nextVariation();
    }
  }

  /** 1 while music plays, fades to 0 within ~1.2s once it stops. */
  float silenceFade(int now)
  {
    int quiet = now - lastAudibleMillis;
    if (quiet <= 400)
      return 1;
    return 1 - (quiet-400)/800.0;
  }

  void nextVariation()
  {
    beamCount = 3 + int(random(MAX_BEAMS - 2));
    laserPattern = int(random(9));
    pulsePattern = int(random(3));
    flowPattern = int(random(2));
    rowVertical = random(1) < 0.5;
    spinDir = random(1) < 0.5 ? 1 : -1;
    sweepSpeed = random(0.25, 0.7);
    waveFreq = random(0.5, 1.2);
    ringsFromCenter = random(1) < 0.5;
    for (int i = 0; i < orbs.length; i++) {
      orbs[i][0] = random(0.04, 0.12);
      orbs[i][1] = random(0.04, 0.12);
      orbs[i][2] = random(TWO_PI);
      orbs[i][3] = random(TWO_PI);
      orbs[i][4] = random(0.06, 0.14);
      orbs[i][5] = random(-30, 30);
    }
    for (int i = 0; i < segs.length; i++) {
      segs[i][0] = random(0.1, 0.35);
      segs[i][1] = random(TWO_PI);
      segs[i][2] = random(0.1, 0.35);
      segs[i][3] = random(TWO_PI);
      segs[i][4] = random(0.2, 0.6) * (random(1) < 0.5 ? -1 : 1);
      segs[i][5] = random(TWO_PI);
    }
    for (int i = 0; i < stars.length; i++) {
      stars[i][0] = random(-0.42, 0.42);
      stars[i][1] = random(-0.42, 0.42);
      stars[i][2] = random(0.2, 0.8);
      stars[i][3] = random(TWO_PI);
    }
    for (int i = 0; i < chase.length; i++) {
      chase[i][2] = random(-0.4, 0.4);
      chase[i][3] = random(-0.4, 0.4);
    }
  }

  /**
   * A big blob of light: drawn as large as possible so it still reads as a
   * bright surface once the beamer light gets washed out in the room.
   */
  void dot(float x, float y, float size, float hue, float sat, float bright)
  {
    stg.noStroke();
    stg.fill(hue, sat, bright);
    stg.ellipse(x, y, size*2, size*2);
  }

  /**
   * A short moving line segment, drawn as a wide bar so it stays clearly
   * visible in the beamer light. Deliberately never across the whole screen.
   */
  void shortLine(float cx, float cy, float angle, float len, float hue, float sat, float bright)
  {
    float dx = cos(angle)*len/2;
    float dy = sin(angle)*len/2;
    stg.strokeCap(ROUND);
    stg.strokeWeight(max(20, stg.getMinRadius()*0.045));
    stg.stroke(hue, sat, bright);
    stg.line(cx-dx, cy-dy, cx+dx, cy+dy);
  }

  /**
   * Techno mode: groups of big light blobs that sweep, spin, snap to new
   * spots on every kick, roll as a sine wave, rain down on the beat, cross
   * each other, step in matrix green formation, tumble as wide scanner
   * strokes or run as an inverse strobe that blacks out on the bass kick.
   */
  void drawLaser(float dt, float bright)
  {
    sweepPhase += dt * sweepSpeed;
    float hue = hueSlider.getValue();
    // never fully saturated: mixing a bit of white into every color makes
    // the beamer output physically brighter
    float sat = bwToggle.getState() ? 0 : 78;
    float minR = stg.getMinRadius();
    float b = bright;
    float size = minR * 0.055 * (1 + kickPulse*0.5);

    switch (laserPattern) {
    case 0:
      {
        // a row of beams beside each other, sweeping across the room
        float spacing = minR * 0.18 * (1 + kickPulse*0.3);
        float sweep = sin(sweepPhase) * 0.8;
        float drift = sin(sweepPhase*0.31) * 0.3;
        for (int i = 0; i < beamCount; i++) {
          float off = (i-(beamCount-1)/2.0) * spacing;
          float x = rowVertical ? sweep*stg.width/2 : off + drift*stg.width/2;
          float y = rowVertical ? off + drift*stg.height/2 : sweep*stg.height/2;
          dot(x, y, size, hue, sat, b);
        }
      }
      break;
    case 1:
      {
        // beams on a spinning circle, breathing with the kick
        float r = minR * (0.25 + 0.12*sin(sweepPhase*0.4)) * (1 + kickPulse*0.3);
        for (int i = 0; i < beamCount; i++) {
          float a = sweepPhase*spinDir + i*TWO_PI/beamCount;
          dot(cos(a)*r, sin(a)*r, size, hue, sat, b);
        }
      }
      break;
    case 2:
      {
        // beams snapping to new spots on every kick
        if (kickNow)
          for (int i = 0; i < beamCount; i++) {
            chase[i][2] = random(-0.4, 0.4);
            chase[i][3] = random(-0.4, 0.4);
          }
        for (int i = 0; i < beamCount; i++) {
          chase[i][0] += (chase[i][2]-chase[i][0]) * min(1, dt*6);
          chase[i][1] += (chase[i][3]-chase[i][1]) * min(1, dt*6);
          dot(chase[i][0]*stg.width, chase[i][1]*stg.height, size, (hue+i*8)%360, sat, b);
        }
      }
      break;
    case 3:
      {
        // wide scanner strokes tumbling through the room
        int n = min(beamCount, segs.length);
        float len = minR * 0.3 * (1 + kickPulse*0.3);
        for (int i = 0; i < n; i++) {
          float[] s = segs[i];
          float cx = sin(sweepPhase*s[0] + s[1]) * stg.width * 0.32;
          float cy = sin(sweepPhase*s[2] + s[3]) * stg.height * 0.32;
          shortLine(cx, cy, sweepPhase*s[4] + s[5], len, (hue+i*12)%360, sat, b);
        }
      }
      break;
    case 4:
      {
        // a sine wave of beams rolling across the room
        int n = beamCount + 2;
        float amp = stg.height * 0.3 * (1 + kickPulse*0.3);
        for (int i = 0; i < n; i++) {
          float x = (i/(float)(n-1) - 0.5) * stg.width * 0.9;
          float y = sin(sweepPhase*1.5*spinDir + i*waveFreq) * amp;
          dot(x, y, size, hue, sat, b);
        }
      }
      break;
    case 5:
      {
        // a few big drops raining down on the beat
        if (kickNow)
          for (int i = 0; i < 2 && rain.size() < 24; i++)
            rain.add(new float[]{ random(-0.45, 0.45), -0.55, random(0.3, 0.6) });
      }
      break;
    case 6:
      {
        // two rows of beams crossing each other
        float spacing = minR * 0.18 * (1 + kickPulse*0.3);
        float shift = sin(sweepPhase) * stg.width * 0.3;
        for (int i = 0; i < beamCount; i++) {
          float off = (i-(beamCount-1)/2.0) * spacing;
          dot(off + shift, -stg.height*0.18, size, hue, sat, b);
          dot(off - shift, stg.height*0.18, size, (hue+40)%360, sat, b);
        }
      }
      break;
    case 7:
      {
        // inverse strobe: the whole screen stays lit at full power and only
        // drops out for a short blackout on every bass kick
        int now = ctrl.millis();
        if (kickNow)
          strobeDropUntil = now + 100;
        if (now > strobeDropUntil) {
          stg.noStroke();
          stg.fill(hue, sat, bright);
          stg.rect(-stg.width/2, -stg.height/2, stg.width, stg.height);
        }
      }
      break;
    default:
      {
        // matrix: green beam columns stepping down in sync with the beat
        if (kickNow)
          matrixTarget++;
        matrixPos += (matrixTarget-matrixPos) * min(1, dt*10);
        int rows = 4;
        float spacing = stg.width * 0.8 / max(1, beamCount-1);
        for (int c = 0; c < beamCount; c++) {
          float x = (c-(beamCount-1)/2.0) * spacing;
          for (int r = 0; r < rows; r++) {
            float yFrac = ((r + matrixPos) % rows) / rows;
            float y = (yFrac - 0.5) * stg.height * 0.9;
            dot(x, y, size, 120, sat, bright*(0.55 + 0.45*yFrac));
          }
        }
      }
    }

    // falling rain drops keep moving even while another pattern plays
    for (int i = rain.size()-1; i >= 0; i--) {
      float[] p = rain.get(i);
      p[1] += p[2] * dt * (1 + kickPulse*0.5);
      if (p[1] > 0.55) {
        rain.remove(i);
        continue;
      }
      dot(p[0]*stg.width, p[1]*stg.height, size, hue, sat, b);
    }
  }

  /**
   * Rhythmic mode: slow wide rings on the kick, plus one secondary pattern
   * per phrase (bouncing beams, beam bursts or orbiting scanner strokes)
   * and sparkles on the hats.
   */
  void drawPulse(int now, float dt, float bright)
  {
    float hue = hueSlider.getValue();
    // never fully saturated: mixing a bit of white into every color makes
    // the beamer output physically brighter
    float sat = bwToggle.getState() ? 0 : 78;
    float minR = stg.getMinRadius();
    float size = minR * 0.05;

    // wide rings that take a few seconds to cross the room
    if (kickNow && now - lastRingMillis > 350 && rings.size() < 6) {
      float rx = ringsFromCenter ? 0 : random(-stg.width*0.25, stg.width*0.25);
      float ry = ringsFromCenter ? 0 : random(-stg.height*0.25, stg.height*0.25);
      rings.add(new float[]{ minR*0.04, rx, ry, random(-20, 20) });
      lastRingMillis = now;
    }
    stg.noFill();
    for (int i = rings.size()-1; i >= 0; i--) {
      float[] ring = rings.get(i);
      ring[0] += minR * dt * 0.2;
      float p = ring[0] / (minR*0.85);
      if (p >= 1) {
        rings.remove(i);
        continue;
      }
      stg.strokeWeight(minR * (0.015 + 0.025*(1-p)));
      stg.stroke((hue+ring[3]+360)%360, sat, bright*min(1, (1-p)*1.6));
      stg.ellipse(ring[1], ring[2], ring[0]*2, ring[0]*2);
    }

    switch (pulsePattern) {
    case 0:
      {
        // a row of beams that leap up on the kick and fall back down
        float floorY = stg.height * 0.22;
        if (kickNow)
          for (int i = 0; i < beamCount; i++)
            bounce[i][1] = -minR * random(1.0, 1.6);
        for (int i = 0; i < beamCount; i++) {
          bounce[i][1] += minR * 5 * dt;
          bounce[i][0] += bounce[i][1] * dt;
          if (bounce[i][0] > floorY) {
            bounce[i][0] = floorY;
            bounce[i][1] = 0;
          }
          float x = (i-(beamCount-1)/2.0) * minR * 0.2;
          dot(x, bounce[i][0], size, hue, sat, bright);
        }
      }
      break;
    case 1:
      {
        // every kick bursts a handful of beams out of a random spot
        if (kickNow && bursts.size() < 30) {
          float bx = random(-stg.width*0.3, stg.width*0.3);
          float by = random(-stg.height*0.3, stg.height*0.3);
          for (int k = 0; k < 6; k++) {
            float ang = random(TWO_PI);
            float sp = minR * random(0.2, 0.5);
            bursts.add(new float[]{ bx, by, cos(ang)*sp, sin(ang)*sp, 1 });
          }
        }
        for (int i = bursts.size()-1; i >= 0; i--) {
          float[] p = bursts.get(i);
          p[4] -= dt*0.9;
          if (p[4] <= 0) {
            bursts.remove(i);
            continue;
          }
          p[2] *= max(0, 1 - 2.5*dt);
          p[3] *= max(0, 1 - 2.5*dt);
          p[0] += p[2]*dt;
          p[1] += p[3]*dt;
          dot(p[0], p[1], size, hue, sat, bright*min(1, p[4]*1.8));
        }
      }
      break;
    default:
      {
        // two short scanner strokes orbiting, snapping around on the snare
        if (snareNow)
          orbitTarget = random(TWO_PI);
        orbitAngle += (orbitTarget-orbitAngle) * min(1, dt*6) + dt*0.3;
        float r = minR * 0.3;
        float ob = bright * (0.75 + 0.25*max(snarePulse, kickPulse));
        for (int j = 0; j < 2; j++) {
          float a = orbitAngle + j*PI;
          shortLine(cos(a)*r, sin(a)*r, a+HALF_PI, minR*0.26, (hue+180)%360, sat, ob);
        }
      }
    }

    if (hatNow && sparks.size() < 30)
      sparks.add(new float[]{ random(-stg.width/2, stg.width/2), random(-stg.height/2, stg.height/2), 1 });
    stg.noStroke();
    for (int i = sparks.size()-1; i >= 0; i--) {
      float[] s = sparks.get(i);
      s[2] -= dt*2;
      if (s[2] <= 0) {
        sparks.remove(i);
        continue;
      }
      stg.fill(hue, sat*0.5, bright*min(1, s[2]*1.5));
      float d = minR * 0.03 * s[2] + 6;
      stg.ellipse(s[0], s[1], d, d);
    }
  }

  /**
   * Calm mode: either soft orbs drifting on lissajous paths or a breathing
   * constellation of dim beams, both following the music level.
   */
  void drawFlow(float dt, float bright)
  {
    flowPhase += dt;
    if (aHueToggle.getState())
      hueSlider.setValue((hueSlider.getValue() + 3*dt) % 360);

    float hue = hueSlider.getValue();
    // never fully saturated: mixing a bit of white into every color makes
    // the beamer output physically brighter
    float sat = bwToggle.getState() ? 0 : 78;
    float threshold = max(ctrl.minLevelSlider.getValue(), 0.01);
    float loud = constrain(smoothLevel / (threshold*4), 0.6, 1);
    float minR = stg.getMinRadius();

    if (flowPattern == 0) {
      for (float[] o : orbs) {
        float x = sin(flowPhase * o[0] * TWO_PI + o[2]) * stg.width * 0.38;
        float y = sin(flowPhase * o[1] * TWO_PI + o[3]) * stg.height * 0.38;
        float d = minR * o[4] * (0.7 + 0.5*loud);
        dot(x, y, d, (hue + o[5] + 360) % 360, sat, bright*loud);
      }
    } else {
      for (float[] st : stars) {
        float breathe = 0.5 + 0.5 * (0.5 + 0.5*sin(flowPhase*st[2] + st[3]));
        dot(st[0]*stg.width, st[1]*stg.height, minR*0.045, hue, sat, bright*loud*breathe);
      }
    }
  }
}
