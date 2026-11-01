import json, urllib.request, concurrent.futures
from pathlib import Path
root=Path(__file__).resolve().parent.parent/'Models'
files=json.load(urllib.request.urlopen('https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base.en?recursive=true'))
jobs=[(f'https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/{x["path"]}',root/Path(x['path']).relative_to('openai_whisper-base.en')) for x in files if x['type']=='file']
jobs += [(f'https://huggingface.co/openai/whisper-base.en/resolve/main/{name}',root/name) for name in ['tokenizer.json','tokenizer_config.json']]
def get(job):
 url,path=job
 path.parent.mkdir(parents=True,exist_ok=True)
 urllib.request.urlretrieve(url,path)
 return str(path.relative_to(root))
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 for name in pool.map(get,jobs): print(name,flush=True)
