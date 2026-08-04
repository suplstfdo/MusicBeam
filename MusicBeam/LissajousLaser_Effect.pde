class LissajousLaser_Effect extends Effect
{

  LissajousLaser_Effect(MusicBeam controller, int y)
  {
    super(controller, y);

    speedSlider = cp5.addSlider("speed"+getName()).setRange(0.01, 1).setValue(0.3).setPosition(0, 5).setSize(395, 45).setGroup(controlGroup);
    speedSlider.getCaptionLabel().set("Speed").align(ControlP5.RIGHT, ControlP5.CENTER);

    trailSlider = cp5.addSlider("trail"+getName()).setRange(5, 60).setValue(40).setPosition(0, 55).setSize(395, 45).setGroup(controlGroup);
    trailSlider.getCaptionLabel().set("Trail").align(ControlP5.RIGHT, ControlP5.CENTER);

    sizeSlider = cp5.addSlider("size"+getName()).setRange(4, 40).setValue(14).setPosition(0, 105).setSize(395, 45).setGroup(controlGroup);
    sizeSlider.getCaptionLabel().set("Dot Size").align(ControlP5.RIGHT, ControlP5.CENTER);

    hueSlider = cp5.addSlider("hue"+getName()).setRange(0, 360).setSize(295, 45).setPosition(50, 155).setGroup(controlGroup);
    hueSlider.getCaptionLabel().set("hue").align(ControlP5.RIGHT, ControlP5.CENTER);
    hueSlider.setValue(0);
    HueControlListener hL = new HueControlListener();
    hueSlider.addListener(hL);

    aHueToggle = cp5.addToggle("ahue"+getName()).setPosition(0, 155).setSize(45, 45).setGroup(controlGroup);
    aHueToggle.getCaptionLabel().set("A").align(ControlP5.CENTER, ControlP5.CENTER);
    aHueToggle.setState(true);

    bwToggle = ctrl.cp5.addToggle("bw"+getName()).setPosition(350, 155).setSize(45, 45).setGroup(controlGroup);
    bwToggle.getCaptionLabel().set("BW").align(ControlP5.CENTER, ControlP5.CENTER);
    bwToggle.setState(true);
  }

  public String getName()
  {
    return "Lissajous";
  }

  char triggeredByKey() {
    return 'd';
  }

  Slider speedSlider, trailSlider, sizeSlider, hueSlider;

  Toggle aHueToggle, bwToggle;

  float t = 0;

  float phaseX = 0;

  int fig = 0;

  int lastFigChange = 0;

  int[][] figs = {
    {1, 2}, {3, 2}, {3, 4}, {2, 3}, {1, 3}
  };

  void draw()
  {
    float fr = max(frameRate, 10);
    float dt = speedSlider.getValue()*2/fr;
    t += dt;

    if ((isKick() || effect_manual_triggered) && millis()-lastFigChange > 2000) {
      fig = (fig+1)%figs.length;
      lastFigChange = millis();
    }
    if (isSnare())
      phaseX = (phaseX+HALF_PI)%TWO_PI;

    float ax = figs[fig][0];
    float ay = figs[fig][1];
    float w = stg.width*0.4;
    float h = stg.height*0.4;
    int n = int(trailSlider.getValue());
    float size = sizeSlider.getValue();
    float sat = bwToggle.getState()?0:100;

    for (int i=n-1; i>=0; i--) {
      float tt = t-i*dt*0.8;
      float f = 1-i/(float)n;
      stg.fill(hueSlider.getValue(), sat, 100*f);
      float s = size*(0.3+0.7*f);
      stg.ellipse(w*sin(ax*tt+phaseX), h*sin(ay*tt), s, s);
    }
    if (isHat()) {
      stg.fill(hueSlider.getValue(), sat, 100);
      stg.ellipse(w*sin(ax*t+phaseX), h*sin(ay*t), size*1.8, size*1.8);
    }

    if (aHueToggle.getState() && (isKick()||isSnare()))
      hueSlider.setValue((hueSlider.getValue()+1)%360);
  }
}
