class LaserTunnel_Effect extends Effect
{

  LaserTunnel_Effect(MusicBeam controller, int y)
  {
    super(controller, y);

    speedSlider = cp5.addSlider("speed"+getName()).setRange(0.05, 1).setValue(0.3).setPosition(0, 5).setSize(395, 45).setGroup(controlGroup);
    speedSlider.getCaptionLabel().set("Expand Speed").align(ControlP5.RIGHT, ControlP5.CENTER);

    weightSlider = cp5.addSlider("weight"+getName()).setRange(1, 10).setValue(3).setPosition(0, 55).setSize(395, 45).setGroup(controlGroup);
    weightSlider.getCaptionLabel().set("Line Weight").align(ControlP5.RIGHT, ControlP5.CENTER);

    maxRingsSlider = cp5.addSlider("maxrings"+getName()).setRange(1, 6).setValue(3).setPosition(0, 105).setSize(395, 45).setGroup(controlGroup);
    maxRingsSlider.getCaptionLabel().set("Max Rings").align(ControlP5.RIGHT, ControlP5.CENTER);

    tiltToggle = cp5.addToggle("tilt"+getName()).setSize(395, 45).setPosition(0, 155).setGroup(controlGroup);
    tiltToggle.getCaptionLabel().set("Tilt").align(ControlP5.CENTER, ControlP5.CENTER);

    hueSlider = cp5.addSlider("hue"+getName()).setRange(0, 360).setSize(295, 45).setPosition(50, 205).setGroup(controlGroup);
    hueSlider.getCaptionLabel().set("hue").align(ControlP5.RIGHT, ControlP5.CENTER);
    hueSlider.setValue(0);
    HueControlListener hL = new HueControlListener();
    hueSlider.addListener(hL);

    aHueToggle = cp5.addToggle("ahue"+getName()).setPosition(0, 205).setSize(45, 45).setGroup(controlGroup);
    aHueToggle.getCaptionLabel().set("A").align(ControlP5.CENTER, ControlP5.CENTER);
    aHueToggle.setState(true);

    bwToggle = ctrl.cp5.addToggle("bw"+getName()).setPosition(350, 205).setSize(45, 45).setGroup(controlGroup);
    bwToggle.getCaptionLabel().set("BW").align(ControlP5.CENTER, ControlP5.CENTER);
    bwToggle.setState(true);

    rings = new LinkedList();
  }

  public String getName()
  {
    return "LaserTunnel";
  }

  char triggeredByKey() {
    return 'e';
  }

  Slider speedSlider, weightSlider, maxRingsSlider, hueSlider;

  Toggle tiltToggle, aHueToggle, bwToggle;

  LinkedList<Float[]> rings;

  int lastSpawn = 0;

  float rot = 0;

  void draw()
  {
    float fr = max(frameRate, 10);
    float speed = speedSlider.getValue();

    if ((isKick() || effect_manual_triggered)
      && rings.size() < int(maxRingsSlider.getValue())
      && millis()-lastSpawn > 350) {
      Float[] ring = {
        0.0f
      };
      rings.add(ring);
      lastSpawn = millis();
    }
    if (isSnare())
      for (Float[] ring : rings)
        ring[0] += 0.03;

    if (tiltToggle.getState()) {
      rot = (rot+0.15*speed/fr)%TWO_PI;
      rotate(rot);
    }

    stg.noFill();
    stg.strokeWeight(weightSlider.getValue());
    float maxDiameter = stg.getMinRadius()*0.95;
    float aspect = tiltToggle.getState()?0.8:1;

    for (int i=rings.size()-1; i>=0; i--) {
      Float[] ring = rings.get(i);
      float p = ring[0];
      if (p >= 1) {
        rings.remove(i);
        continue;
      }
      // brief ramp-in so a new ring doesn't pop in at full brightness
      float rampIn = min(1, p/0.06);
      stg.stroke(hueSlider.getValue(), bwToggle.getState()?0:100, 100*rampIn*(1-p));
      float d = maxDiameter*(0.05+0.95*p);
      stg.ellipse(0, 0, d, d*aspect);
      ring[0] = p+speed/(fr*1.5);
    }

    stg.noStroke();
    stg.strokeWeight(1);

    if (aHueToggle.getState() && isKick())
      hueSlider.setValue((hueSlider.getValue()+1)%360);
  }
}
