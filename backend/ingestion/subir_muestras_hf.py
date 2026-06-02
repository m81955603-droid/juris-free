"""
Sube las muestras juridicas a Hugging Face Dataset
Ejecutar una sola vez desde local
"""
import os
import sys
from pathlib import Path
from huggingface_hub import HfApi

HF_TOKEN = os.getenv("HF_TOKEN")
HF_REPO = os.getenv("HF_MUESTRAS_REPO", "maja-juridico/muestras-juridicas")
MUESTRAS_DIR = Path(r"C:\proyectos\juris-free\muestras")

def subir_muestras():
    api = HfApi(token=HF_TOKEN)
    
    print(f"Subiendo muestras desde {MUESTRAS_DIR} a {HF_REPO}...")
    
    archivos = list(MUESTRAS_DIR.rglob("*.docx"))
    print(f"Total archivos: {len(archivos)}")
    
    # Subir en lotes de 50
    lote = []
    for i, archivo in enumerate(archivos):
        ruta_relativa = archivo.relative_to(MUESTRAS_DIR)
        lote.append((str(archivo), str(ruta_relativa)))
        
        if len(lote) >= 50 or i == len(archivos) - 1:
            print(f"Subiendo lote {i//50 + 1}... ({i+1}/{len(archivos)})")
            try:
                api.upload_folder(
                    folder_path=str(MUESTRAS_DIR),
                    repo_id=HF_REPO,
                    repo_type="dataset",
                    token=HF_TOKEN,
                    ignore_patterns=["*.gitattributes", "*.pdf", "*.doc"],
                    commit_message=f"Lote {i//50 + 1} de muestras juridicas"
                )
                lote = []
                break  # upload_folder sube todo de una vez
            except Exception as e:
                print(f"Error: {e}")
                sys.exit(1)
    
    print("Muestras subidas correctamente a HuggingFace")

if __name__ == "__main__":
    subir_muestras()