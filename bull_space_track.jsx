/*
  Bull Space Track -> Null
  ------------------------
  1. В композиции выдели ОДИН слой — видео с быком.
  2. File > Scripts > Run Script File... и выбери этот файл.
  Скрипт создаст Null "Bull Space Track": он повторяет движение КАМЕРЫ
  относительно быка (трек по корпусу, голова исключена), 0.83–3.0 сек видео.
  Плашки, привязанные к нему, висят в пространстве перед быком —
  бык крутит головой, а плашки стоят.
  Привязывай плашки через Parent (pick whip) НА 1.33 СЕК —
  в этот момент Scale = 100% и Rotation = 0.
*/
(function () {
    var DATA = {"fps":24,"src_width":854,"ref_frame":32,"frames":[20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72],"position":[[550.02,260.9],[547.42,258.74],[544.56,256.0],[542.36,253.31],[540.98,250.92],[540.24,248.83],[539.94,247.03],[539.94,245.52],[540.09,244.23],[540.25,243.03],[540.32,241.91],[540.29,240.9],[540.28,239.99],[540.4,239.15],[540.64,238.41],[540.88,237.8],[541.07,237.32],[541.2,236.94],[541.29,236.67],[541.33,236.49],[541.37,236.38],[541.39,236.32],[541.41,236.29],[541.41,236.29],[541.41,236.29],[541.42,236.29],[541.43,236.27],[541.49,236.17],[541.69,235.87],[542.22,235.15],[543.35,233.68],[545.37,231.05],[548.57,226.74],[552.91,220.35],[557.82,211.94],[561.87,202.4],[562.65,193.52],[558.66,186.71],[551.49,181.73],[543.65,177.68],[536.38,174.02],[530.06,170.56],[524.8,167.36],[520.54,164.61],[517.16,162.33],[514.53,160.47],[512.55,159.04],[511.14,158.04],[510.17,157.43],[509.45,157.06],[508.9,156.91],[508.5,156.97],[508.28,157.15]],"scale":[124.803,121.62,117.817,114.335,111.421,108.962,106.858,105.08,103.59,102.337,101.314,100.537,100.0,99.656,99.431,99.265,99.141,99.055,99.0,98.965,98.94,98.919,98.905,98.897,98.89,98.881,98.863,98.824,98.718,98.46,97.937,97.02,95.596,93.664,91.364,88.689,85.277,80.922,76.11,71.505,67.329,63.498,60.073,57.219,54.965,53.223,51.925,51.0,50.326,49.786,49.325,48.944,48.677],"rotation":[-1.582,-1.526,-1.418,-1.256,-1.061,-0.87,-0.708,-0.572,-0.448,-0.328,-0.215,-0.107,0.0,0.109,0.209,0.29,0.351,0.394,0.423,0.44,0.45,0.456,0.459,0.46,0.459,0.459,0.461,0.475,0.524,0.65,0.92,1.429,2.294,3.596,5.293,7.151,8.676,9.468,9.648,9.539,9.337,9.177,9.108,9.086,9.062,9.021,8.974,8.94,8.922,8.909,8.893,8.876,8.866]};
    var comp = app.project.activeItem;
    if (!(comp instanceof CompItem)) { alert("Открой композицию с видео."); return; }
    if (comp.selectedLayers.length !== 1) { alert("Выдели один слой — видео с быком."); return; }
    var vid = comp.selectedLayers[0];
    var vidName = vid.name.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    var t0 = vid.startTime;

    app.beginUndoGroup("Bull Space Track");
    var nl = comp.layers.addNull();
    nl.name = "Bull Space Track";
    nl.moveBefore(vid);
    nl.label = 9;

    var cb = nl.property("ADBE Effect Parade").addProperty("ADBE Checkbox Control");
    cb.name = "Use Rotation";
    cb.property(1).setValue(1);

    var tr = nl.property("ADBE Transform Group");
    tr.property("ADBE Anchor Point").setValue([50, 50]);  // центр нулла 100x100
    var pos = tr.property("ADBE Position"), sc = tr.property("ADBE Scale"), rot = tr.property("ADBE Rotate Z");

    var times = [], pv = [], sv = [], rv = [];
    for (var i = 0; i < DATA.frames.length; i++) {
        times.push(t0 + DATA.frames[i] / DATA.fps);
        pv.push(DATA.position[i]);
        sv.push([DATA.scale[i], DATA.scale[i]]);
        rv.push(DATA.rotation[i]);
    }
    pos.setValuesAtTimes(times, pv);
    sc.setValuesAtTimes(times, sv);
    rot.setValuesAtTimes(times, rv);
    var props = [pos, sc, rot];
    for (var p = 0; p < props.length; p++)
        for (var k = 1; k <= props[p].numKeys; k++)
            props[p].setInterpolationTypeAtKey(k, KeyframeInterpolationType.LINEAR, KeyframeInterpolationType.LINEAR);

    // ключи в пикселях видео 854x480 -> пересчёт под реальное разрешение и положение слоя видео
    pos.expression = 'var L = thisComp.layer("' + vidName + '");\nvar k = L.width / ' + DATA.src_width + ';\nL.toComp(value * k);';
    rot.expression = 'effect("Use Rotation")("Checkbox") == 1 ? value : 0;';

    nl.inPoint = t0 + DATA.frames[0] / DATA.fps;
    nl.outPoint = t0 + (DATA.frames[DATA.frames.length - 1] + 1) / DATA.fps;
    comp.time = t0 + DATA.ref_frame / DATA.fps;
    app.endUndoGroup();
    alert("Готово! Null 'Bull Space Track' создан.\nИндикатор времени поставлен на 1.33 сек — привяжи плашки к нуллу через Parent.");
})();
