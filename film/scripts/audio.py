"""Deterministic original score. No sampled or generated media dependencies."""
from pathlib import Path
import numpy as np, wave, json
ROOT=Path(__file__).resolve().parents[1]; SR=48000; FPS=60; SECONDS=30
N=SR*SECONDS; music=np.zeros((N,2)); effects=np.zeros((N,2)); beat_stem=np.zeros(N)
rng=np.random.default_rng(20261018)
def put(dst,s,t,vol=1,pan=0):
 i=round(t*SR); l=min(len(s),N-i)
 if l<=0:return
 dst[i:i+l,0]+=s[:l]*vol*np.sqrt((1-pan)/2)
 dst[i:i+l,1]+=s[:l]*vol*np.sqrt((1+pan)/2)
def tone(freq,dur,kind='pluck'):
 t=np.arange(round(dur*SR))/SR
 if kind=='pad':
  e=(1-np.exp(-t*5))*np.exp(-t*.65)*np.minimum(1,(dur-t)*3)
  return e*(np.sin(2*np.pi*freq*t)+.18*np.sin(2*np.pi*freq*2*t))
 return (np.sin(2*np.pi*freq*t)+.25*np.sin(2*np.pi*2*freq*t))*np.exp(-t*8)*(1-np.exp(-t*200))
def hz(m):return 440*2**((m-69)/12)
chords=[[48,55,59,62,64],[45,52,55,59,60],[41,48,52,55,57],[43,50,53,57,60]]
for bar in range(15):
 chord=chords[(bar//2)%4]; start=bar*2
 for k,m in enumerate(chord):put(music,tone(hz(m+12),2.8,'pad'),start,.045,(k-2)*.25)
 put(music,tone(hz(chord[0]-12),1.8,'pad'),start,.14)
 for step in range(4):
  note=chord[[2,4,3,1][(step+bar)%4]]+24
  put(music,tone(hz(note),.75),start+step*.5,.065,(-1 if step%2 else 1)*.38)
for b in range(60):
 start=b*.5; t=np.arange(int(.24*SR))/SR
 phase=2*np.pi*(48*t+55*(1-np.exp(-t*32))/32)
 kick=np.sin(phase)*np.exp(-t*24)*(1-np.exp(-t*700))
 put(music,kick,start,.17 if b%4==0 else .10)
 i=round(start*SR);beat_stem[i:i+len(kick)]+=kick
 if b%2==1:
  t=np.arange(int(.09*SR))/SR; noise=rng.normal(0,1,len(t));noise=np.r_[0,np.diff(noise)]
  put(music,noise*np.exp(-t*70),start,.012,.25)
events=[(150,'whoosh'),(270,'complete'),(360,'whoosh'),(420,'click'),(510,'whoosh'),(600,'click'),(690,'click'),(720,'whoosh'),(780,'click'),(900,'confirm'),(990,'complete'),(1110,'whoosh'),(1170,'click'),(1260,'whoosh'),(1440,'whoosh'),(1500,'click'),(1590,'resolve')]
for frame,kind in events:
 if kind=='whoosh':
  dur=.22;t=np.arange(round(dur*SR))/SR;z=rng.normal(0,1,len(t));z=np.convolve(z,np.ones(11)/11,'same');s=z*np.sin(np.pi*t/dur)**2;put(effects,s,frame/FPS,.045,-.15)
 elif kind=='click':
  t=np.arange(int(.055*SR))/SR;s=np.sin(2*np.pi*1500*t)*np.exp(-t*110);put(effects,s,frame/FPS,.035)
 else:
  for k,m in enumerate([72,79,83]):put(effects,tone(hz(m),.65),frame/FPS+k*.025,.026,k*.2-.2)
fade=np.minimum(1,(SECONDS-np.arange(N)/SR)/1.0).clip(0,1);music*=fade[:,None];effects*=fade[:,None]
def wav(path,x):
 with wave.open(str(path),'wb') as w:w.setnchannels(x.shape[1] if x.ndim==2 else 1);w.setsampwidth(2);w.setframerate(SR);w.writeframes((np.clip(x,-1,1)*32767).astype('<i2').tobytes())
(ROOT/'public/audio').mkdir(parents=True,exist_ok=True)
wav(ROOT/'public/audio/music-raw.wav',music);wav(ROOT/'public/audio/mix-raw.wav',music+effects);wav(ROOT/'public/audio/sfx.wav',effects)
# Beat onset detection on isolated rhythmic stem, 1 ms windows; kick attack begins at the assigned sample.
energy=np.sqrt(np.mean(beat_stem.reshape(-1,48)**2,axis=1));det=[]
for b in range(60):
 base=b*500; idx=np.flatnonzero(energy[base:base+100]>.01);det.append(round((base+int(idx[0]))/1000*FPS) if len(idx) else None)
durations=[150,210,150,210,210,180,150,180,150,210]
scenes=[]
for i,n in enumerate(['hook','scan','select','preserve','review','result','analyze','status','theme','signoff']):
 scenes.append({'id':n,'start':sum(durations[:i]),'duration':durations[i]})
names=['scanEnter','scanComplete','selectEnter','selectAll','preserveEnter','unselectBackup','reviewOpen','reviewEnter','quitOption','confirm','resultComplete','analyzeEnter','openFolder','statusEnter','themeEnter','themeSwitch','signoffEnter']
actions=[{'id':name,'frame':f,'kind':k,'visualFrame':f,'errorFrames':0} for name,(f,k) in zip(names,events)]
timing={'fps':FPS,'durationFrames':1800,'bpm':120,'beats':list(range(0,1800,30)),'detectedBeatFrames':det,'beatDetectionMethod':'1ms RMS onset > .01 in isolated kick stem','maxBeatErrorFrames':max(abs(a-b*30) for b,a in enumerate(det)),'climaxFrames':[900,1590],'voice':[],'scenes':scenes,'actions':actions,'handoff':{'x':1320,'y':540},'motion':{'enterFrames':28,'exitFrames':18,'staggerFrames':7}}
(ROOT/'production/timing.json').write_text(json.dumps(timing,ensure_ascii=False,indent=2)+'\n')
print('Beat max error',timing['maxBeatErrorFrames']);print('Music RMS',np.sqrt(np.mean(music**2)),'SFX RMS',np.sqrt(np.mean(effects**2)))
