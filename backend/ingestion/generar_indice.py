"""
Genera indice JSON de las muestras y lo sube a HuggingFace
"""
import os
import json
from pathlib import Path
from huggingface_hub import HfApi

HF_TOKEN = os.getenv("HF_TOKEN")
HF_REPO = "maja-juridico/muestras-juridicas"
MUESTRAS_DIR = Path(r"C:\proyectos\juris-free\muestras")

CARPETA_CATEGORIA = {
    "1.- MATERIAL ANTIGUO":                                "Material Antiguo",
    "2.- SUPER MALETA PAR ABOGADOS":                      "Super Maleta",
    "3.- DERECHO ACTUAL 1":                               "Derecho Actual 1",
    "4.- DERECHO ACTUAL 2":                               "Derecho Actual 2",
    "5.- DERECHO ACTUAL 3":                               "Derecho Actual 3",
    "6.- CODIGO PRECESAL CIVIL CONCORDADO":               "Codigo Procesal Civil",
    "12.- PROCEDIMIENTO_ FAMILIAR, NIÑA NIÑO ADOLECENTE": "Procedimiento Familiar"
}

CARPETA_ICONO = {
    "1.- MATERIAL ANTIGUO":          "📁",
    "2.- SUPER MALETA PAR ABOGADOS": "💼",
    "3.- DERECHO ACTUAL 1":          "📚",
    "4.- DERECHO ACTUAL 2":          "📚",
    "5.- DERECHO ACTUAL 3":          "📚",
    "6.- CODIGO PRECESAL CIVIL CONCORDADO": "⚖",
    "12.- PROCEDIMIENTO_ FAMILIAR, NIÑA NIÑO ADOLECENTE": "👨‍👩‍👧"
}

def generar_indice():
    index = []
    for carpeta_principal in sorted(os.listdir(MUESTRAS_DIR)):
        carpeta_path = MUESTRAS_DIR / carpeta_principal
        if not carpeta_path.is_dir():
            continue
        categoria = CARPETA_CATEGORIA.get(carpeta_principal, carpeta_principal)
        icono = CARPETA_ICONO.get(carpeta_principal, "📄")

        for root, dirs, files in os.walk(carpeta_path):
            dirs.sort()
            for filename in sorted(files):
                if not filename.lower().endswith(('.docx', '.doc')):
                    continue
                full_path = Path(root) / filename
                rel_path = full_path.relative_to(MUESTRAS_DIR)
                subcarpeta = Path(root).relative_to(carpeta_path)
                subcarpeta_str = str(subcarpeta) if str(subcarpeta) != "." else ""

                try:
                    tamanio = full_path.stat().st_size
                except:
                    tamanio = 0

                doc_id = str(rel_path).replace('\\', '/').replace(' ', '_')
                hf_url = f"https://huggingface.co/datasets/{HF_REPO}/resolve/main/{str(rel_path).replace(chr(92), '/')}"

                index.append({
                    "id": doc_id,
                    "nombre": full_path.stem,
                    "carpeta": carpeta_principal,
                    "subcarpeta": subcarpeta_str,
                    "categoria": categoria,
                    "icono": icono,
                    "ruta_relativa": str(rel_path).replace('\\', '/'),
                    "hf_url": hf_url,
                    "tamanio": tamanio
                })

    print(f"Total archivos indexados: {len(index)}")

    output_path = MUESTRAS_DIR.parent / "backend" / "ingestion" / "indice_muestras.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"total": len(index), "archivos": index}, f, ensure_ascii=False, indent=2)
    print(f"Indice guardado en {output_path}")

    # Subir indice a HuggingFace
    api = HfApi(token=HF_TOKEN)
    api.upload_file(
        path_or_fileobj=str(output_path),
        path_in_repo="indice.json",
        repo_id=HF_REPO,
        repo_type="dataset",
        token=HF_TOKEN,
        commit_message="Actualizar indice de muestras"
    )
    print("Indice subido a HuggingFace correctamente")

if __name__ == "__main__":
    generar_indice()