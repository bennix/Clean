"""Measure final delivery. Human judgement lives in independent review reports."""
from pathlib import Path
import subprocess,json,re,numpy as np
R=Path(__file__).resolve().parents[1]; video=R.parent/'docs/assets/clean-product-film.mp4'
def run(args): return subprocess.check_output(args)
probe=json.loads(run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(video)]))
v=next(s for s in probe['streams'] if s['codec_type']=='video')
a=next(s for s in probe['streams'] if s['codec_type']=='audio')
raw=run(['ffmpeg','-v','error','-i',str(video),'-vf','scale=160:90,format=gray','-f','rawvideo','-pix_fmt','gray','-'])
frames=np.frombuffer(raw,dtype=np.uint8).reshape(-1,90,160);diff=np.mean(np.abs(np.diff(frames.astype(float),axis=0)),axis=(1,2));runlen=0;maxrun=0
for d in diff:
 runlen=runlen+1 if d<.001 else 0;maxrun=max(maxrun,runlen)
thumbIdenticalFrames=int(np.sum(diff<.001))
# Full-resolution decoded hashes detect actual duplicated frames; thumbnail differences are a stricter near-still diagnostic.
md5=run(['ffmpeg','-v','error','-i',str(video),'-map','0:v','-f','framemd5','-']).decode()
hashes=[line.split(',')[-1].strip() for line in md5.splitlines() if not line.startswith('#')]
exactDuplicates=sum(a==b for a,b in zip(hashes,hashes[1:]))
freezeLog=subprocess.run(['ffmpeg','-hide_banner','-i',str(video),'-vf','freezedetect=n=-60dB:d=0.5','-an','-f','null','-'],capture_output=True,text=True).stderr
freezeDurations=[float(x) for x in re.findall(r'freeze_duration: ([0-9.]+)',freezeLog)]
black=int(np.sum(np.mean(frames,axis=(1,2))<1))
def L(h):
 c=np.array([int(h[i:i+2],16)/255 for i in (1,3,5)]); c=np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4);return c@np.array([.2126,.7152,.0722])
pairs=[('#14201c','#f5f7f4'),('#ffffff','#13171d'),('#c7e6b7','#13171d'),('#14201c','#c7e6b7'),('#14201c','#4a9d83'),('#ffffff','#14201c')]
contrast=[{'foreground':x,'background':y,'ratio':round((max(L(x),L(y))+.05)/(min(L(x),L(y))+.05),2)} for x,y in pairs]
log=subprocess.run(['ffmpeg','-hide_banner','-i',str(video),'-af','loudnorm=I=-14:TP=-1:LRA=8:print_format=json','-f','null','-'],capture_output=True,text=True).stderr
m=re.findall(r'\{\s*"input_i".*?\}',log,re.S);loud=json.loads(m[-1])
# Decode actual video colors rather than assuming the source survived YUV conversion.
colors=[]
for sec,target in [(0,(245,247,244)),(5,(19,23,29))]:
 b=run(['ffmpeg','-v','error','-ss',str(sec),'-i',str(video),'-vf','crop=2:2:40:40','-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-']);rgb=np.frombuffer(b,dtype=np.uint8).reshape(-1,3).mean(axis=0);colors.append({'time':sec,'sourceRGB':target,'encodedRGB':rgb.tolist(),'maxChannelError':int(np.max(np.abs(rgb-np.array(target))))})
import wave
with wave.open(str(R/'public/audio/mix.wav'),'rb') as w:
 source=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').reshape(-1,2).mean(axis=1).astype(float)/32768
encoded=np.frombuffer(run(['ffmpeg','-v','error','-i',str(video),'-vn','-ar','48000','-ac','1','-f','f32le','-']),dtype='<f4').astype(float)
timing=json.loads((R/'production/timing.json').read_text())
offsets=[]
for event in timing['actions']:
 center=round(event['frame']/60*48000);windowStart=max(120,center-480);windowEnd=min(len(source)-120,center+4800);ref=source[windowStart:windowEnd]
 scores=[np.dot(ref,encoded[windowStart+lag:windowEnd+lag])/(np.linalg.norm(ref)*np.linalg.norm(encoded[windowStart+lag:windowEnd+lag])+1e-12) for lag in range(-100,101)]
 lag=int(np.argmax(scores))-100;offsets.append({'id':event['id'],'lagSamples':lag,'lagFrames':round(lag/800,4),'correlation':round(max(scores),5)})
checks={'dimensions' :v['width']==1920 and v['height']==1080,'fps':v['r_frame_rate']=='60/1','frames':int(v['nb_frames'])==1800,'duration':abs(float(probe['format']['duration'])-30)<.001,'audioStereo48k':a['channels']==2 and a['sample_rate']=='48000','noBlackFrames':black==0,'noFreezeOverHalfSecond':maxrun<=30 and not freezeDurations,'totalDuplicateFramesUnderOneSecond':exactDuplicates<=60,'contrast':min(c['ratio'] for c in contrast)>=4.5,'brandColor':max(c['maxChannelError'] for c in colors)<=3,'loudness':abs(float(loud['input_i'])+14)<=.6,'truePeak':float(loud['input_tp'])<=-1,'beatOnsetWithinOneFrame':timing['maxBeatErrorFrames']<=1,'encodedAudioAlignmentWithinOneFrame':max(abs(o['lagFrames']) for o in offsets)<=1}
checks={k:bool(v) for k,v in checks.items()}
report={'file':str(video.relative_to(R.parent)),'checks':checks,'passed':all(checks.values()),'video':{k:v[k] for k in ['width','height','r_frame_rate','nb_frames','duration']},'containerDuration':probe['format']['duration'],'identicalFrameThresholdMeanLuma':.001,'longestIdenticalRunFrames':maxrun,'blackFrames':black,'fullResolutionDuplicateFrames':exactDuplicates,'thumbnailNearStillFrames':thumbIdenticalFrames,'ffmpegFreezeDurations':freezeDurations,'contrast':contrast,'encodedColors':colors,'audio':{'integratedLUFS':loud['input_i'],'truePeakDBTP':loud['input_tp'],'LRA':loud['input_lra']},'sync':{'encodedAudioEventOffsets':offsets,'sourceTimelineMaxBeatErrorFrames':timing['maxBeatErrorFrames'],'note':'Beat stem onset measured at1ms; event start frames use shared timing. Independent reviewer checks actual video events.'},'limits':['Frame-difference pass does not prove compelling motion; independent director review required.','UI reconstruction and example data must remain labeled.','Final speaker/headphone listening and subjective quality require human ears; no fabricated listening claim.']}
(R/'production/quality.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False,indent=2))
if not report['passed']:raise SystemExit(1)
