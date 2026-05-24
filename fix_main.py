content = open(r'C:\proyectos\juris-free\backend\api\main.py', encoding='utf-8').read()
old = '    logging.info(f"Descargando muestras desde {hf_repo}...")\n    try:'
new = '    logging.info(f"Descargando muestras desde {hf_repo}...")\n    logging.info(f"HF_TOKEN presente: {bool(hf_token)}, REPO: {hf_repo}")\n    try:'
content = content.replace(old, new)
open(r'C:\proyectos\juris-free\backend\api\main.py', 'w', encoding='utf-8').write(content)
print('OK')
