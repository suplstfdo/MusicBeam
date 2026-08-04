class LaserArray_Effect extends Effect
{

  LaserArray_Effect(MusicBeam controller, int y)
  {
    super(controller, y);

    countSlider = cp5.addSlider("count"+getName()).setPosition(0, 5).setSize(395, 45).setGroup(controlGroup);
    countSlider.setRange(2, 8).setValue(5);
    countSlider.getCaptionLabel().set("Beams").align(ControlP5.RIGHT, ControlP5.CENTER);

    speedSlider = cp5.addSlider("speed"+getName()).setRange(0.01, 1).setValue(0.25).setPosition(0, 55).setSize(395, 45).setGroup(controlGroup);
    speedSlider.getCaptionLabel().set("Speed").align(ControlP5.RIGHT, ControlP5.CENTER);

    sizeSlider = cp5.addSlider("size"+getName()).setRange(8, 60).setValue(25).setPosition(0, 105).setSize(395, 45).setGroup(controlGroup);
    sizeSlider.getCaptionLabel().set("Dot Size").align(ControlP5.RIGHT, ControlP5.CENTER);

    fanToggle = cp5.addToggle("fan"+getName()).setSize(395, 45).setPosition(0, 155).setGroup(controlGroup);
    fanToggle.getCaptionLabel().set("Fan").align(ControlP5.CENTER, ControlP5.CENTER);
    fanToggle.setState(true);

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
  }

  public String getName()
  {
    return "LaserArray";
  }

  char triggeredByKey() {
    return 'c';
  }

  Slider countSlider, speedSlider, sizeSlider, hueSlider;

  Toggle fanToggle, aHueToggle, bwToggle;

  float angle = 0, targetAngle = 0;

  float spread = 0.7, targetSpread = 0.7;

  float bobPhase = 0;

  void draw()
  {
    fanToggle.getCaptionLabel().set(fanToggle.getState() ? "Fan" : "Bar");

    float fr = max(frameRate, 10);
    float speed = speedSlider.getValue();

    if (isKick() || effect_manual_triggered)
      targetAngle = random(-QUARTER_PI, QUARTER_PI);
    if (isSnare())
      targetSpread = random(0.35, 1.0);

    float ease = 6*speed/fr;
    angle += (targetAngle-angle)*ease;
    spread += (targetSpread-spread)*ease;
    bobPhase = (bobPhase+0.4*speed*TWO_PI/fr)%TWO_PI;

    int n = int(countSlider.getValue());
    float size = sizeSlider.getValue();
    stg.fill(hueSlider.getValue(), bwToggle.getState()?0:100, 100);

    rotate(angle);
    if (fanToggle.getState()) {
      float r = stg.getMinRadius()*0.42;
      float arc = spread*PI*0.6;
      for (int i=0; i<n; i++) {
        float a = -arc/2+arc*i/(n-1);
        stg.ellipse(r*sin(a), -r*cos(a)+stg.getMinRadius()*0.1, size, size);
      }
    } else {
      float total = spread*stg.width*0.8;
      for (int i=0; i<n; i++) {
        float x = -total/2+total*i/(n-1);
        float y = sin(bobPhase)*stg.height*0.12+sin(bobPhase+i*0.6)*stg.height*0.04;
        stg.ellipse(x, y, size, size);
      }
    }
    if (aHueToggle.getState() && (isKick()||isSnare()))
      hueSlider.setValue((hueSlider.getValue()+1)%360);
  }
}
