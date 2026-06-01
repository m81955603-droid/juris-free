"""
Scraper de la Gaceta Oficial de Bolivia
Descarga nuevas normas y las sube a Hugging Face Dataset
"""
import os
import time
import json
import logging
import requests
from datetime import datetime, timedelta
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

HF_TOKEN = os.getenv("HF_TOKEN")
HF_REPO = os.getenv("HF_DATASET_REPO", "maja-juridico/normas-bolivia")
GACETA_URL = "https://gacetaoficialdebolivia.gob.bo"
OUTPUT_DIR = Path(os.getenv("TEMP", "/tmp")) / "normas_scrapeadas"
OUTPUT_DIR.mkdir(exist_ok=True)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "es-ES,es;q=0.9",
}


def buscar_normas_recientes(dias=7):
    """Busca normas publicadas en los ultimos N dias en la Gaceta Oficial"""
    fecha_desde = (datetime.now() - timedelta(days=dias)).strftime("%Y-%m-%d")
    fecha_hasta = datetime.now().strftime("%Y-%m-%d")
    
    logger.info(f"Buscando normas desde {fecha_desde} hasta {fecha_hasta}")
    
    try:
        # API de busqueda de la Gaceta
        url = f"{GACETA_URL}/normas/buscar"
        params = {
            "fechaDesde": fecha_desde,
            "fechaHasta": fecha_hasta,
            "tipo": "ley,decreto",
            "page": 1,
            "limit": 50
        }
        resp = requests.get(url, params=params, headers=HEADERS, timeout=30)
        
        if resp.status_code == 200:
            return resp.json().get("resultados", [])
        else:
            logger.warning(f"Gaceta respondio {resp.status_code}, intentando metodo alternativo")
            return buscar_via_html(fecha_desde, fecha_hasta)
            
    except Exception as e:
        logger.error(f"Error buscando en Gaceta: {e}")
        return buscar_via_html(fecha_desde, fecha_hasta)


def buscar_via_html(fecha_desde, fecha_hasta):
    """Metodo alternativo: scraping HTML de la Gaceta"""
    normas = []
    try:
        url = f"{GACETA_URL}/normas"
        resp = requests.get(url, headers=HEADERS, timeout=30)
        
        if resp.status_code != 200:
            logger.error(f"No se pudo acceder a la Gaceta: {resp.status_code}")
            return []
        
        from html.parser import HTMLParser
        
        class GacetaParser(HTMLParser):
            def __init__(self):
                super().__init__()
                self.normas = []
                self.current = {}
                self.in_norma = False
                
            def handle_starttag(self, tag, attrs):
                attrs_dict = dict(attrs)
                if tag == "a" and "norma" in attrs_dict.get("href", ""):
                    self.in_norma = True
                    self.current = {"url": GACETA_URL + attrs_dict["href"]}
                    
            def handle_data(self, data):
                if self.in_norma and data.strip():
                    self.current["titulo"] = data.strip()
                    self.normas.append(self.current)
                    self.in_norma = False
        
        parser = GacetaParser()
        parser.feed(resp.text)
        return parser.normas[:20]
        
    except Exception as e:
        logger.error(f"Error en scraping HTML: {e}")
        return []


def extraer_texto_pdf(url_pdf):
    """Descarga y extrae texto de un PDF de la Gaceta"""
    try:
        resp = requests.get(url_pdf, headers=HEADERS, timeout=60)
        if resp.status_code != 200:
            return ""
        
        import fitz
        doc = fitz.open(stream=resp.content, filetype="pdf")
        texto = ""
        for page in doc:
            texto += page.get_text() + "\n"
        doc.close()
        return texto.strip()
        
    except Exception as e:
        logger.error(f"Error extrayendo PDF {url_pdf}: {e}")
        return ""


def subir_a_huggingface(normas_nuevas):
    """Sube las normas nuevas al dataset de Hugging Face"""
    if not HF_TOKEN:
        logger.error("HF_TOKEN no configurado")
        return False
        
    try:
        from huggingface_hub import HfApi
        api = HfApi(token=HF_TOKEN)
        
        # Descargar dataset actual
        normas_actuales = []
        try:
            from huggingface_hub import hf_hub_download
            path = hf_hub_download(
                repo_id=HF_REPO,
                filename="normas_bolivia.json",
                repo_type="dataset",
                token=HF_TOKEN
            )
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                normas_actuales = data.get("documentos", [])
        except Exception:
            logger.info("Dataset vacio o no existe, creando nuevo")
        
        # IDs existentes para no duplicar
        ids_existentes = {n.get("id") for n in normas_actuales}
        
        # Agregar nuevas normas
        agregadas = 0
        for norma in normas_nuevas:
            if norma.get("id") not in ids_existentes:
                normas_actuales.append(norma)
                ids_existentes.add(norma["id"])
                agregadas += 1
        
        if agregadas == 0:
            logger.info("No hay normas nuevas para agregar")
            return True
        
        # Guardar y subir
        output = {
            "generado": datetime.now().isoformat(),
            "total_documentos": len(normas_actuales),
            "documentos": normas_actuales
        }
        
        tmp_path = str(Path(os.getenv("TEMP", "/tmp")) / "normas_bolivia_updated.json")
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)
        
        api.upload_file(
            path_or_fileobj=tmp_path,
            path_in_repo="normas_bolivia.json",
            repo_id=HF_REPO,
            repo_type="dataset",
            token=HF_TOKEN,
            commit_message=f"Actualización automática: {agregadas} normas nuevas - {datetime.now().strftime('%Y-%m-%d')}"
        )
        
        logger.info(f"Dataset actualizado: {agregadas} normas nuevas, total {len(normas_actuales)}")
        return True
        
    except Exception as e:
        logger.error(f"Error subiendo a HuggingFace: {e}")
        return False


def subir_normas_base():
    """Sube las normas base del JSON local a Hugging Face"""
    base_path = Path(__file__).parent / "normas_bolivia.json"
    if not base_path.exists():
        logger.error("normas_bolivia.json no encontrado")
        return False
    
    try:
        from huggingface_hub import HfApi
        api = HfApi(token=HF_TOKEN)
        
        api.upload_file(
            path_or_fileobj=str(base_path),
            path_in_repo="normas_bolivia.json",
            repo_id=HF_REPO,
            repo_type="dataset",
            token=HF_TOKEN,
            commit_message="Subida inicial de normas bolivianas"
        )
        logger.info("Normas base subidas a HuggingFace correctamente")
        return True
    except Exception as e:
        logger.error(f"Error subiendo normas base: {e}")
        return False


def run_scraper(dias=1):
    """Ejecuta el scraper completo"""
    logger.info("=== Iniciando scraper Gaceta Oficial Bolivia ===")
    
    normas_nuevas = buscar_normas_recientes(dias=dias)
    logger.info(f"Encontradas {len(normas_nuevas)} normas recientes")
    
    normas_procesadas = []
    for i, norma in enumerate(normas_nuevas):
        logger.info(f"Procesando {i+1}/{len(normas_nuevas)}: {norma.get('titulo', 'Sin titulo')}")
        
        texto = ""
        if norma.get("url_pdf"):
            texto = extraer_texto_pdf(norma["url_pdf"])
        
        norma_procesada = {
            "id": f"gaceta-{norma.get('numero', i)}-{datetime.now().year}",
            "tipo": norma.get("tipo", "ley").lower(),
            "titulo": norma.get("titulo", "Sin titulo"),
            "area": detectar_area(norma.get("titulo", "")),
            "fuente": "Gaceta Oficial de Bolivia",
            "fecha": norma.get("fecha", datetime.now().strftime("%Y-%m-%d")),
            "resumen": texto[:500] if texto else norma.get("titulo", ""),
            "articulos": extraer_articulos(texto) if texto else []
        }
        normas_procesadas.append(norma_procesada)
        time.sleep(2)  # Pausa para no saturar la Gaceta
    
    if normas_procesadas:
        subir_a_huggingface(normas_procesadas)
    
    logger.info("=== Scraper completado ===")


def detectar_area(titulo):
    """Detecta el area legal basandose en el titulo"""
    titulo_lower = titulo.lower()
    if any(w in titulo_lower for w in ["penal", "delito", "crimen", "fiscal"]):
        return "penal"
    if any(w in titulo_lower for w in ["civil", "contrato", "propiedad", "herencia"]):
        return "civil"
    if any(w in titulo_lower for w in ["laboral", "trabajo", "empleado", "salario"]):
        return "laboral"
    if any(w in titulo_lower for w in ["familia", "matrimonio", "divorcio", "menor"]):
        return "familiar"
    if any(w in titulo_lower for w in ["constitucion", "derecho", "garantia", "amparo"]):
        return "constitucional"
    if any(w in titulo_lower for w in ["administrativo", "municipal", "gobierno", "estado"]):
        return "administrativo"
    return "general"


def extraer_articulos(texto):
    """Extrae articulos del texto de una ley"""
    import re
    articulos = []
    patron = r'Art[íi]culo\s+(\d+)[°\.]?\s*[\.\-\)]\s*([^\n]+(?:\n(?!Art[íi]culo\s+\d)[^\n]+)*)'
    matches = re.findall(patron, texto, re.IGNORECASE)
    
    for num, contenido in matches[:20]:  # Max 20 articulos
        articulos.append({
            "num": num,
            "texto": contenido.strip()[:500]
        })
    return articulos


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "subir-base":
        subir_normas_base()
    else:
        run_scraper(dias=7)