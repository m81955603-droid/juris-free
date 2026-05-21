# JURIS-FREE Bolivia — Biblioteca Legal
# Scraper + Pipeline de ingestin + Busqueda semantica
# PowerShell 7+

param([string]$Ruta = "C:\proyectos\juris-free")

$fe   = "$Ruta\frontend\src\app"
$back = "$Ruta\backend"
$ErrorActionPreference = "Continue"

function OK   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function PASO { param($m) Write-Host "`n--- $m ---" -ForegroundColor Cyan }
function INFO { param($m) Write-Host "  ->  $m" -ForegroundColor White }

Write-Host "`n  JURIS-FREE — Biblioteca Legal Bolivia`n" -ForegroundColor Cyan

# ══════════════════════════════════════════════════════
# 1. DEPENDENCIAS PYTHON PARA SCRAPER
# ══════════════════════════════════════════════════════
PASO "Instalando dependencias Python para scraper"
Set-Location "$back"
& ".\venv\Scripts\pip.exe" install requests beautifulsoup4 lxml httpx 2>&1 | Out-Null
OK "requests + beautifulsoup4 + lxml instalados"

# ══════════════════════════════════════════════════════
# 2. SCRAPER PRINCIPAL — GACETA OFICIAL + TCP + TSJ
# ══════════════════════════════════════════════════════
PASO "Scraper de normativa boliviana"
New-Item -ItemType Directory -Path "$back\ingestion" -Force | Out-Null

[System.IO.File]::WriteAllText("$back\ingestion\bolivia_scraper.py", @'
"""
JURIS-FREE Bolivia — Scraper de normativa legal boliviana
Fuentes:
  - Gaceta Oficial de Bolivia (gacetaoficialdebolivia.gob.bo)
  - Tribunal Constitucional Plurinacional (tribunalconstitucional.bo)
  - Organo Judicial (organojudicial.gob.bo)
  - Leyes conocidas hardcoded (CPE, codigos principales)
"""

import requests
import json
import time
import logging
import os
from datetime import datetime
from typing import Optional
from bs4 import BeautifulSoup

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "es-BO,es;q=0.9",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
}

OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "normas_bolivia.json")


def fetch_safe(url: str, timeout: int = 15) -> Optional[str]:
    """Fetch con manejo de errores."""
    try:
        r = requests.get(url, headers=HEADERS, timeout=timeout, verify=False)
        r.raise_for_status()
        r.encoding = r.apparent_encoding or "utf-8"
        return r.text
    except Exception as e:
        logger.warning(f"Error fetching {url}: {e}")
        return None


# ── BASE DE CONOCIMIENTO HARDCODED (normativa clave boliviana) ─────────────────
# Estas normas son de dominio publico y conocimiento juridico fundamental

NORMAS_FUNDAMENTALES = [
    {
        "id": "cpe-2009",
        "tipo": "constitucion",
        "titulo": "Constitucion Politica del Estado Plurinacional de Bolivia 2009",
        "area": "constitucional",
        "fuente": "Asamblea Constituyente",
        "fecha": "2009-02-07",
        "articulos_clave": [
            {"num": "1", "texto": "Bolivia se constituye en un Estado Unitario Social de Derecho Plurinacional Comunitario, libre, independiente, soberano, democratico, intercultural, descentralizado y con autonomias."},
            {"num": "8", "texto": "El Estado asume y promueve como principios etico-morales de la sociedad plural: ama qhilla, ama llulla, ama suwa (no seas flojo, no seas mentiroso ni seas ladron), suma qamana (vivir bien), nandereko (vida armoniosa), teko kavi (vida buena), ivi maraei (tierra sin mal) y qhapaj nan (camino o vida noble)."},
            {"num": "13", "texto": "Los derechos reconocidos por esta Constitucion son inviolables, universales, interdependientes, indivisibles y progresivos. El Estado tiene el deber de promoverlos, protegerlos y respetarlos. Los derechos establecidos en esta Constitucion no dejan de reconocerse por la enumeracion de ellos. La clasificacion de los derechos establecida en esta Constitucion no determina jerarquia alguna ni superioridad de unos derechos sobre otros."},
            {"num": "14", "texto": "Todo ser humano tiene personalidad y capacidad juridica con arreglo a las leyes y goza de los derechos reconocidos por esta Constitucion, sin distincion alguna. Queda prohibida y sancionada toda forma de discriminacion fundada en razon de sexo, color, edad, orientacion sexual, identidad de genero, origen, cultura, nacionalidad, ciudadania, idioma, credo religioso, ideologia, filiacion politica o filosofica, estado civil, condicion economica o social, tipo de ocupacion, grado de instruccion, discapacidad, embarazo, u otras que tengan por objetivo o resultado anular o menoscabar el reconocimiento, goce o ejercicio, en condiciones de igualdad, de los derechos de toda persona."},
            {"num": "115", "texto": "Toda persona sera protegida oportuna y efectivamente por los jueces y tribunales en el ejercicio de sus derechos e intereses legitimos. El Estado garantiza el derecho al debido proceso, a la defensa y a una justicia plural, pronta, oportuna, gratuita, transparente y sin dilaciones."},
            {"num": "116", "texto": "Se garantiza la presuncion de inocencia. Durante el proceso, en caso de duda sobre la norma aplicable, regira la mas favorable al imputado o procesado."},
            {"num": "119", "texto": "Las partes en conflicto gozaran de igualdad de oportunidades para ejercer durante el proceso las facultades y los derechos que les asistan, sea por la via ordinaria, por la via agroambiental o por la jurisdiccion indigena originaria campesina."},
            {"num": "120", "texto": "Toda persona tiene derecho a ser oida por una autoridad jurisdiccional competente, independiente e imparcial, y no podra ser juzgada por comisiones especiales ni sometida a otras autoridades jurisdiccionales que las establecidas con anterioridad al hecho de la causa."},
            {"num": "178", "texto": "La potestad de impartir justicia emana del pueblo boliviano y se sustenta en los principios de independencia, imparcialidad, seguridad juridica, publicidad, probidad, celeridad, gratuidad, pluralismo juridico, interculturalidad, equidad, servicio a la sociedad, participacion ciudadana, armonia social y respeto a los derechos."},
            {"num": "256", "texto": "Los tratados e instrumentos internacionales en materia de derechos humanos que hayan sido firmados, ratificados o a los que se hubiera adherido el Estado, que declaren derechos mas favorables a los contenidos en la Constitucion, se aplicaran de manera preferente sobre esta."}
        ],
        "resumen": "Ley fundamental del Estado Plurinacional de Bolivia. Establece la organizacion del Estado, derechos fundamentales, garantias constitucionales, estructura de poderes y principios del ordenamiento juridico boliviano."
    },
    {
        "id": "ley-12760-codigo-civil",
        "tipo": "codigo",
        "titulo": "Codigo Civil de Bolivia — Ley 12760",
        "area": "civil",
        "fuente": "Congreso Nacional",
        "fecha": "1976-08-02",
        "articulos_clave": [
            {"num": "1", "texto": "Las personas son individuales o colectivas. Son individuales los seres humanos. Son colectivas las asociaciones, fundaciones y las sociedades a las que la ley reconoce personalidad juridica."},
            {"num": "4", "texto": "La capacidad juridica es inherente a toda persona y no admite restricciones que no sean establecidas por ley. Los actos de disposicion o administracion de bienes que realicen las personas con discapacidad o con capacidades diferentes, tienen validez juridica."},
            {"num": "519", "texto": "El contrato tiene fuerza de ley entre las partes contratantes. No puede ser disuelto sino por consentimiento mutuo o por las causas autorizadas por la ley."},
            {"num": "520", "texto": "El contrato debe ser ejecutado de buena fe y obliga no solo a lo que se ha expresado en el, sino tambien a todos los efectos que deriven conforme a su naturaleza, segun la ley, o a falta de esta segun los usos y la equidad."},
            {"num": "549", "texto": "El contrato sera nulo: 1. Por faltar en el contrato la forma requerida por ley. 2. Por faltar el objeto o ser este ilicito. 3. Por faltar la causa o ser esta ilicita. 4. Por ilicitud del motivo que impulsio a las partes a contratar, cuando ese motivo ha sido determinante de la voluntad de ambas partes y es comun a ellas. 5. Por error esencial sobre la naturaleza o sobre el objeto del contrato. 6. En los demas casos determinados por la ley."},
            {"num": "568", "texto": "Si la prestacion de una de las partes se hace imposible por causa no imputable a ninguna de ellas, el contrato se disuelve y cada parte puede repetir lo que haya cumplido."},
            {"num": "984", "texto": "Todo hecho ilicito del hombre que causa un dano a otro, obliga a aquel por cuya culpa sucedio, a reparar el dano."},
            {"num": "1492", "texto": "Los derechos se extinguen por la prescripcion cuando su titular no los ejerce durante el tiempo que la ley establece."}
        ],
        "resumen": "Codigo Civil boliviano que regula las relaciones juridicas entre personas: contratos, obligaciones, propiedad, familia, sucesiones y responsabilidad civil."
    },
    {
        "id": "ley-1768-codigo-penal",
        "tipo": "codigo",
        "titulo": "Codigo Penal de Bolivia — Ley 1768",
        "area": "penal",
        "fuente": "Congreso Nacional",
        "fecha": "1997-03-10",
        "articulos_clave": [
            {"num": "1", "texto": "Nadie sera condenado o sometido a medida de seguridad por un hecho que no este expresamente previsto como delito por ley penal vigente al tiempo en que se comete, ni sometido a penas o medidas de seguridad que no se encuentren establecidas en ella."},
            {"num": "13", "texto": "La culpabilidad y no el resultado es el limite de la pena. Queda proscrita toda forma de responsabilidad objetiva. La pena no podra sobrepasar la culpabilidad del autor. Se entiende por culpabilidad el reproche que se formula a la persona que ha realizado un acto tipico y antijuridico, cuando podia haber actuado de manera diferente."},
            {"num": "23", "texto": "Es autor quien realiza el hecho punible por si solo, en coautoria o sirviendose de otro como instrumento."},
            {"num": "251", "texto": "El que con intencion de matar causare la muerte de una persona, sera sancionado con presidio de diez a veinte anos. Si la muerte se produce como consecuencia de una accion destinada a causar lesion, la sancion sera de cinco a quince anos de presidio."},
            {"num": "325", "texto": "El que mediante engano o abuso de confianza, en perjuicio de otro, se apoderare de una cosa mueble ajena o le procurare un beneficio economico ilicito, incurrira en la pena de prision de uno a cinco anos y multa de sesenta a doscientos dias."},
            {"num": "331", "texto": "El que apoderare de una cosa mueble ajena, sera sancionado con prision de uno a cinco anos."},
            {"num": "346", "texto": "El que causare a otro lesion en el cuerpo o en la salud, sera sancionado con la pena de tres meses a dos anos de prision. La pena sera de seis meses a tres anos de prision si la lesion produjere incapacidad para el trabajo por mas de un mes o enfermedad por igual tiempo."}
        ],
        "resumen": "Codigo Penal boliviano. Define los delitos, las penas y las medidas de seguridad aplicables. Regula la responsabilidad penal, autoria, participacion, y los tipos penales del ordenamiento boliviano."
    },
    {
        "id": "ley-603-familias",
        "tipo": "codigo",
        "titulo": "Codigo de las Familias y del Proceso Familiar — Ley 603",
        "area": "familiar",
        "fuente": "Asamblea Legislativa Plurinacional",
        "fecha": "2014-11-19",
        "articulos_clave": [
            {"num": "1", "texto": "La presente Ley tiene por objeto regular las relaciones juridicas de la familia, la estructura del proceso familiar y los principios que los rigen."},
            {"num": "139", "texto": "El matrimonio es una institucion social permanente y voluntaria concertada entre dos personas para establecer una comunidad de vida, sobre la base del amor, el respeto mutuo, la igualdad de derechos y obligaciones."},
            {"num": "204", "texto": "El vinculo matrimonial se disuelve por la muerte de uno de los conyuges o por sentencia de divorcio o desvinculacion."},
            {"num": "205", "texto": "El divorcio o desvinculacion del vinculo matrimonial puede realizarse de forma: 1. De mutuo acuerdo. 2. Por decision unilateral de uno de los conyuges."},
            {"num": "206", "texto": "El divorcio o desvinculacion de mutuo acuerdo de conyuges sin hijas o hijos menores de edad o con hijas o hijos mayores de edad sin discapacidad, podra tramitarse ante Notaria o Notario de Fe Publica o ante la autoridad judicial competente en materia familiar."},
            {"num": "207", "texto": "El divorcio o desvinculacion unilateral se tramitara ante la autoridad judicial competente en materia familiar. La sola voluntad de uno de los conyuges es suficiente para demandar el divorcio o desvinculacion."},
            {"num": "215", "texto": "Los efectos del divorcio o desvinculacion respecto a los hijos e hijas comprenden: 1. Definicion de la guarda y custodia. 2. Regimen de visitas y comunicacion. 3. Asistencia familiar."},
            {"num": "109", "texto": "La asistencia familiar es el derecho que tiene toda persona de recibir de sus parientes proximos los medios necesarios para su subsistencia cuando se encuentra en estado de necesidad."}
        ],
        "resumen": "Regula las relaciones juridicas familiares en Bolivia: matrimonio, union libre, divorcio, filicion, asistencia familiar, adopcion y el proceso familiar ante jueces competentes."
    },
    {
        "id": "ley-439-proceso-civil",
        "tipo": "codigo",
        "titulo": "Codigo Procesal Civil — Ley 439",
        "area": "civil",
        "fuente": "Asamblea Legislativa Plurinacional",
        "fecha": "2013-11-19",
        "articulos_clave": [
            {"num": "1", "texto": "El proceso civil tiene por objeto la efectividad de los derechos sustantivos reconocidos por la ley, a traves del ejercicio de la potestad jurisdiccional del Estado, segun los principios de igualdad, imparcialidad, publico, oral, concentrado y contradictorio."},
            {"num": "3", "texto": "Las autoridades judiciales deben actuar con celeridad, eficacia y eficiencia, sin restricciones ni formalidades que obstaculicen el acceso a la justicia."},
            {"num": "87", "texto": "El recurso de apelacion procede contra las resoluciones enumeradas en el presente Codigo. El plazo para interponer el recurso de apelacion es de diez dias computables desde la notificacion con la resolucion."},
            {"num": "132", "texto": "La demanda debe contener: 1. Nombre y domicilio del demandante y del demandado. 2. Relacion precisa de los hechos. 3. Invocacion del derecho en que se funda. 4. La cosa, cantidad o hecho que se pide. 5. Firma del demandante o su representante."},
            {"num": "221", "texto": "La sentencia debe contener: 1. Lugar y fecha. 2. Nombre de las partes. 3. Resumen de los hechos. 4. Fundamentos de hecho y de derecho. 5. Parte resolutiva clara y precisa. 6. Condena en costas si corresponde. 7. Firma de la autoridad judicial."},
            {"num": "255", "texto": "El recurso de casacion procede contra los autos de vista y las resoluciones de segunda instancia que resuelvan apelaciones de autos definitivos, en los casos previstos en este Codigo."}
        ],
        "resumen": "Regula el proceso civil en Bolivia: demandas, recursos, plazos procesales, medidas cautelares, ejecucion de sentencias y procedimientos especiales."
    },
    {
        "id": "ley-1970-proceso-penal",
        "tipo": "codigo",
        "titulo": "Codigo de Procedimiento Penal — Ley 1970",
        "area": "penal",
        "fuente": "Congreso Nacional",
        "fecha": "1999-03-25",
        "articulos_clave": [
            {"num": "1", "texto": "Nadie sera condenado a pena alguna sin haber sido oido y juzgado previamente en proceso legal; ni la sufre si no ha sido impuesta por sentencia ejecutoriada y por autoridad judicial competente. La ejecucion de la pena privativa de libertad y las medidas de seguridad estaran a cargo del organo judicial."},
            {"num": "5", "texto": "Todo imputado tiene derecho a ser asistido y defendido por un abogado desde el primer acto del proceso hasta la conclusion de la condena. En caso de no poder designarlo, el Estado le asignara un defensor publico."},
            {"num": "6", "texto": "Todo imputado tiene derecho a conocer de manera previa y detallada la acusacion formulada en su contra; a no declarar contra si mismo; y a la presuncion de inocencia."},
            {"num": "225", "texto": "La aprehension policial procede cuando el delincuente es sorprendido en flagrancia, o cuando existe pedido fundamentado de la Fiscalia. La aprehension no podra durar mas de ocho horas, al cabo de las cuales la policia debera poner al aprehendido a disposicion del fiscal."},
            {"num": "233", "texto": "La detencion preventiva procedera cuando: 1. La existencia de elementos de conviccion suficientes para sostener que el imputado es, con probabilidad, autor o participe de un hecho punible. 2. La existencia de elementos de conviccion suficientes de que el imputado no se sometera al proceso u obstaculizara la averiguacion de la verdad."},
            {"num": "272", "texto": "Las partes podran objetar las resoluciones expresando el agravio que les causa. Los recursos son: la reposicion, la apelacion incidental, la apelacion restringida y el recurso de casacion."}
        ],
        "resumen": "Regula el proceso penal boliviano: investigacion, imputacion, medidas cautelares, juicio oral, recursos y ejecucion de sentencias penales."
    },
    {
        "id": "lgt-trabajo",
        "tipo": "ley",
        "titulo": "Ley General del Trabajo de Bolivia",
        "area": "laboral",
        "fuente": "Gobierno de Bolivia",
        "fecha": "1942-12-08",
        "articulos_clave": [
            {"num": "1", "texto": "El trabajo es un derecho y un deber social. Goza de la proteccion del Estado, el que asegurara condiciones dignas de labor y una remuneracion justa."},
            {"num": "13", "texto": "Cuando el trabajador fuera retirado por el empleador a su voluntad, este pagara una indemnizacion equivalente a un mes de sueldo o salario por cada ano de trabajo continuo, y de manera proporcional si el tiempo de permanencia fuera menor."},
            {"num": "16", "texto": "Son causas que dan lugar al despido sin derecho a desahucio ni beneficios sociales: a) Perjuicio material causado con intension. b) Revelacion de secretos industriales. c) Omision o imprudencia que afecte a la seguridad del trabajo. d) Incumplimiento total o parcial del contrato. e) Robo o hurto. f) Vicios o malos habitos. g) Abandono del trabajo."},
            {"num": "39", "texto": "El salario minimo nacional es la remuneracion minima que tiene derecho a percibir el trabajador por su labor. Ninguna remuneracion podra ser inferior al salario minimo nacional."},
            {"num": "44", "texto": "La jornada efectiva de trabajo no excedera de ocho horas por dia y cuarenta y ocho horas por semana. Las horas de trabajo para los menores de 18 anos, no podran exceder de seis horas diarias."},
            {"num": "52", "texto": "El aguinaldo de Navidad consiste en el pago de un mes de sueldo que los empleadores pagaran a sus empleados hasta el 25 de diciembre de cada ano."}
        ],
        "resumen": "Regula las relaciones laborales en Bolivia: contrato de trabajo, jornada, salario minimo, aguinaldo, vacaciones, beneficios sociales e indemnizacion por despido."
    },
    {
        "id": "ley-2341-admin",
        "tipo": "ley",
        "titulo": "Ley de Procedimiento Administrativo — Ley 2341",
        "area": "administrativo",
        "fuente": "Congreso Nacional",
        "fecha": "2002-04-23",
        "articulos_clave": [
            {"num": "1", "texto": "La presente Ley tiene por objeto establecer las normas que regulan la actividad administrativa y el procedimiento administrativo del sector publico; asimismo, garantizar y regular la impugnacion de actuaciones administrativas que afecten derechos subjetivos e intereses legitimos de los administrados."},
            {"num": "4", "texto": "La actividad administrativa se regira por los principios de: a) Legalidad. b) Buena Fe. c) Presuncion de Legitimidad. d) Imparcialidad. e) Responsabilidad. f) Gratuidad. g) Publicidad. h) Sencillez. i) Celeridad y Economia."},
            {"num": "65", "texto": "Los recursos administrativos son: a) El recurso de revocatoria. b) El recurso jerarquico. Los plazos para interponer estos recursos son de diez dias habiles para la revocatoria y diez dias habiles para el jerarquico, computados desde el dia siguiente a la notificacion."}
        ],
        "resumen": "Regula el procedimiento administrativo boliviano, los principios de la administracion publica y los recursos administrativos (revocatoria y jerarquico)."
    }
]


def scrape_gaceta_reciente():
    """Intenta obtener normas recientes de la Gaceta Oficial."""
    normas = []
    url = "https://www.gacetaoficialdebolivia.gob.bo/normas/buscar"
    html = fetch_safe(url)
    if not html:
        logger.warning("Gaceta Oficial no accesible — usando datos locales")
        return normas

    try:
        soup = BeautifulSoup(html, 'lxml')
        # Buscar enlaces a normas recientes
        links = soup.find_all('a', href=True)
        for link in links[:20]:
            href = link.get('href', '')
            texto = link.get_text(strip=True)
            if any(kw in texto.lower() for kw in ['ley', 'decreto', 'resolucion']) and len(texto) > 20:
                normas.append({
                    "titulo": texto[:200],
                    "url": href if href.startswith('http') else f"https://www.gacetaoficialdebolivia.gob.bo{href}"
                })
    except Exception as e:
        logger.warning(f"Error parseando Gaceta: {e}")

    return normas[:10]


def scrape_tcp_sentencias():
    """Intenta obtener sentencias recientes del TCP."""
    sentencias = []
    url = "https://www.tribunalconstitucional.bo/sentencias"
    html = fetch_safe(url)
    if not html:
        logger.warning("TCP no accesible desde este entorno")
        return sentencias

    try:
        soup = BeautifulSoup(html, 'lxml')
        for item in soup.find_all(['li', 'tr', 'div'], class_=lambda c: c and 'sentencia' in c.lower())[:10]:
            texto = item.get_text(strip=True)
            if len(texto) > 30:
                sentencias.append({
                    "titulo": texto[:300],
                    "tipo": "sentencia",
                    "area": "constitucional"
                })
    except Exception as e:
        logger.warning(f"Error parseando TCP: {e}")

    return sentencias


def generar_base_conocimiento():
    """Genera el archivo JSON con toda la base de conocimiento."""
    logger.info("Iniciando generacion de base de conocimiento legal boliviana...")

    todos_los_documentos = []

    # 1. Normas fundamentales hardcoded (siempre disponibles)
    for norma in NORMAS_FUNDAMENTALES:
        doc = {
            "id": norma["id"],
            "tipo": norma["tipo"],
            "titulo": norma["titulo"],
            "area": norma["area"],
            "fuente": norma.get("fuente", ""),
            "fecha": norma.get("fecha", ""),
            "resumen": norma.get("resumen", ""),
            "contenido": norma.get("resumen", ""),
            "articulos": norma.get("articulos_clave", []),
            "origen": "base_hardcoded"
        }
        todos_los_documentos.append(doc)
        logger.info(f"  + {norma['titulo'][:60]}...")

    # 2. Intentar scraping de fuentes externas (puede fallar)
    logger.info("Intentando scraping de Gaceta Oficial...")
    gaceta = scrape_gaceta_reciente()
    logger.info(f"  Gaceta: {len(gaceta)} normas obtenidas")

    logger.info("Intentando scraping TCP...")
    sentencias = scrape_tcp_sentencias()
    logger.info(f"  TCP: {len(sentencias)} sentencias obtenidas")

    # Guardar resultado
    resultado = {
        "generado": datetime.now().isoformat(),
        "total_documentos": len(todos_los_documentos),
        "documentos": todos_los_documentos,
        "scraping_gaceta": gaceta,
        "scraping_tcp": sentencias
    }

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(resultado, f, ensure_ascii=False, indent=2)

    logger.info(f"Base de conocimiento guardada: {OUTPUT_FILE}")
    logger.info(f"Total: {len(todos_los_documentos)} documentos legales")
    return resultado


if __name__ == "__main__":
    resultado = generar_base_conocimiento()
    print(f"\nBase de conocimiento generada: {resultado['total_documentos']} documentos")
'@)
OK "bolivia_scraper.py"

# ══════════════════════════════════════════════════════
# 3. RUTA DE BIBLIOTECA EN FASTAPI
# ══════════════════════════════════════════════════════
PASO "Ruta FastAPI para biblioteca legal"

[System.IO.File]::WriteAllText("$back\api\routes\library.py", @'
"""
JURIS-FREE Bolivia — API de Biblioteca Legal
Busqueda en normativa boliviana: CPE, codigos, leyes, sentencias TCP
"""

from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import Optional, List
import json
import os
import re

router = APIRouter()

# Cache en memoria del conocimiento legal
_knowledge_cache = None
NORMAS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'ingestion', 'normas_bolivia.json')


def load_knowledge():
    global _knowledge_cache
    if _knowledge_cache is None:
        try:
            if os.path.exists(NORMAS_FILE):
                with open(NORMAS_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    _knowledge_cache = data.get('documentos', [])
            else:
                _knowledge_cache = []
        except Exception as e:
            print(f"Error cargando base de conocimiento: {e}")
            _knowledge_cache = []
    return _knowledge_cache


class SearchResult(BaseModel):
    id: str
    tipo: str
    titulo: str
    area: str
    resumen: str
    articulos_relevantes: List[dict]
    score: float


class ArticuloResult(BaseModel):
    norma_id: str
    norma_titulo: str
    numero: str
    texto: str
    area: str


@router.get("/search", response_model=List[SearchResult])
async def search_library(
    q: str = Query(..., min_length=2, description="Termino de busqueda"),
    area: Optional[str] = Query(None, description="Filtrar por area legal"),
    tipo: Optional[str] = Query(None, description="Filtrar por tipo (ley, codigo, sentencia)"),
    limit: int = Query(10, le=20)
):
    """Busqueda en la biblioteca legal boliviana."""
    docs = load_knowledge()
    query_lower = q.lower()
    query_words = set(query_lower.split())

    results = []
    for doc in docs:
        # Filtros
        if area and doc.get('area') != area:
            continue
        if tipo and doc.get('tipo') != tipo:
            continue

        # Scoring simple por relevancia
        score = 0.0
        titulo_lower = doc.get('titulo', '').lower()
        resumen_lower = doc.get('resumen', '').lower()

        # Coincidencia en titulo (mayor peso)
        for word in query_words:
            if word in titulo_lower:
                score += 3.0

        # Coincidencia en resumen
        for word in query_words:
            if word in resumen_lower:
                score += 1.0

        # Buscar en articulos
        articulos_relevantes = []
        for art in doc.get('articulos', []):
            art_texto = art.get('texto', '').lower()
            art_score = sum(1 for w in query_words if w in art_texto)
            if art_score > 0:
                score += art_score * 0.5
                articulos_relevantes.append({
                    "numero": art.get('num', ''),
                    "texto": art.get('texto', '')[:300],
                    "relevancia": art_score
                })

        if score > 0:
            # Ordenar articulos por relevancia
            articulos_relevantes.sort(key=lambda x: x['relevancia'], reverse=True)
            results.append(SearchResult(
                id=doc.get('id', ''),
                tipo=doc.get('tipo', ''),
                titulo=doc.get('titulo', ''),
                area=doc.get('area', ''),
                resumen=doc.get('resumen', '')[:400],
                articulos_relevantes=articulos_relevantes[:3],
                score=score
            ))

    # Ordenar por score
    results.sort(key=lambda x: x.score, reverse=True)
    return results[:limit]


@router.get("/normas", response_model=List[dict])
async def list_normas(
    area: Optional[str] = None,
    tipo: Optional[str] = None
):
    """Lista todas las normas disponibles."""
    docs = load_knowledge()
    result = []
    for doc in docs:
        if area and doc.get('area') != area:
            continue
        if tipo and doc.get('tipo') != tipo:
            continue
        result.append({
            "id": doc.get('id'),
            "tipo": doc.get('tipo'),
            "titulo": doc.get('titulo'),
            "area": doc.get('area'),
            "fecha": doc.get('fecha', ''),
            "total_articulos": len(doc.get('articulos', []))
        })
    return result


@router.get("/norma/{norma_id}")
async def get_norma(norma_id: str):
    """Obtiene una norma completa por ID."""
    docs = load_knowledge()
    for doc in docs:
        if doc.get('id') == norma_id:
            return doc
    return {"error": "Norma no encontrada"}


@router.get("/articulo")
async def search_articulo(
    norma: str = Query(..., description="ID de la norma"),
    numero: str = Query(..., description="Numero de articulo")
):
    """Busca un articulo especifico en una norma."""
    docs = load_knowledge()
    for doc in docs:
        if doc.get('id') == norma or norma.lower() in doc.get('titulo', '').lower():
            for art in doc.get('articulos', []):
                if art.get('num') == numero:
                    return {
                        "norma": doc.get('titulo'),
                        "articulo": numero,
                        "texto": art.get('texto'),
                        "area": doc.get('area')
                    }
    return {"error": f"Articulo {numero} no encontrado en {norma}"}


@router.get("/stats")
async def get_stats():
    """Estadisticas de la biblioteca."""
    docs = load_knowledge()
    areas = {}
    tipos = {}
    total_articulos = 0

    for doc in docs:
        area = doc.get('area', 'otro')
        tipo = doc.get('tipo', 'otro')
        areas[area] = areas.get(area, 0) + 1
        tipos[tipo] = tipos.get(tipo, 0) + 1
        total_articulos += len(doc.get('articulos', []))

    return {
        "total_normas": len(docs),
        "total_articulos_indexados": total_articulos,
        "por_area": areas,
        "por_tipo": tipos,
        "fuentes": ["CPE 2009", "Codigo Civil Ley 12760", "Codigo Penal Ley 1768",
                    "Ley 603 Familias", "CPC Ley 439", "CPP Ley 1970", "LGT", "Ley 2341"]
    }
'@)
OK "library.py (API de busqueda)"

# Agregar ruta al main.py
[System.IO.File]::WriteAllText("$back\api\main.py", @'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
import logging
import os

load_dotenv(dotenv_path=r"C:\proyectos\juris-free\backend\.env", override=True)

from .routes import llm, embeddings, health, library

logging.basicConfig(level=logging.INFO)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.info("JURIS-FREE Bolivia API iniciando...")
    logging.info(f"Gemini:     {'OK' if os.getenv('GEMINI_API_KEY') else 'FALTA'}")
    logging.info(f"Groq:       {'OK' if os.getenv('GROQ_API_KEY') else 'FALTA'}")
    logging.info(f"Cerebras:   {'OK' if os.getenv('CEREBRAS_API_KEY') else 'FALTA'}")
    logging.info(f"OpenRouter: {'OK' if os.getenv('OPENROUTER_API_KEY') else 'FALTA'}")
    logging.info(f"SambaNova:  {'OK' if os.getenv('SAMBANOVA_API_KEY') else 'FALTA'}")
    yield

app = FastAPI(title="JURIS-FREE Bolivia API", version="1.0.0", lifespan=lifespan)

app.add_middleware(CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"])

app.include_router(health.router)
app.include_router(llm.router,        prefix="/api/v1/llm",        tags=["LLM"])
app.include_router(embeddings.router, prefix="/api/v1/embeddings", tags=["Embeddings"])
app.include_router(library.router,    prefix="/api/v1/library",    tags=["Biblioteca"])
'@)
OK "main.py actualizado con ruta /api/v1/library"

# ══════════════════════════════════════════════════════
# 4. EJECUTAR SCRAPER PARA GENERAR BASE DE CONOCIMIENTO
# ══════════════════════════════════════════════════════
PASO "Generando base de conocimiento legal"
Set-Location "$back"
INFO "Ejecutando scraper (puede tomar 30-60 segundos)..."

$result = & ".\venv\Scripts\python.exe" "ingestion\bolivia_scraper.py" 2>&1
Write-Host $result -ForegroundColor DarkGray

if (Test-Path "ingestion\normas_bolivia.json") {
    $json = Get-Content "ingestion\normas_bolivia.json" | ConvertFrom-Json
    OK "Base de conocimiento generada: $($json.total_documentos) normas legales"
} else {
    Write-Host "  !! El archivo JSON no se genero — verificar logs" -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════
# 5. FRONTEND — COMPONENTE BIBLIOTECA
# ══════════════════════════════════════════════════════
PASO "Componente Biblioteca Legal (Angular)"
New-Item -ItemType Directory -Path "$fe\features\library" -Force | Out-Null

[System.IO.File]::WriteAllText("$fe\features\library\library.component.ts", @'
import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';

interface SearchResult {
  id: string;
  tipo: string;
  titulo: string;
  area: string;
  resumen: string;
  articulos_relevantes: { numero: string; texto: string; relevancia: number }[];
  score: number;
}

interface Norma {
  id: string;
  tipo: string;
  titulo: string;
  area: string;
  fecha: string;
  total_articulos: number;
}

interface LibStats {
  total_normas: number;
  total_articulos_indexados: number;
  por_area: Record<string, number>;
  por_tipo: Record<string, number>;
  fuentes: string[];
}

@Component({
  selector: 'app-library',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './library.component.html',
  styleUrls: ['./library.component.scss']
})
export class LibraryComponent implements OnInit {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl + '/api/v1/library';

  searchQuery    = '';
  selectedArea   = '';
  selectedTipo   = '';
  isSearching    = signal(false);
  results        = signal<SearchResult[]>([]);
  normas         = signal<Norma[]>([]);
  stats          = signal<LibStats | null>(null);
  selectedNorma  = signal<any>(null);
  view           = signal<'search' | 'browse' | 'detail'>('search');
  hasSearched    = signal(false);

  readonly areas = [
    { valor: '',               label: 'Todas las areas' },
    { valor: 'civil',          label: 'Derecho Civil' },
    { valor: 'penal',          label: 'Derecho Penal' },
    { valor: 'laboral',        label: 'Derecho Laboral' },
    { valor: 'constitucional', label: 'Derecho Constitucional' },
    { valor: 'familiar',       label: 'Derecho Familiar' },
    { valor: 'administrativo', label: 'Derecho Administrativo' }
  ];

  readonly tipos = [
    { valor: '',             label: 'Todos los tipos' },
    { valor: 'constitucion', label: 'Constitucion' },
    { valor: 'codigo',       label: 'Codigo' },
    { valor: 'ley',          label: 'Ley' },
    { valor: 'sentencia',    label: 'Sentencia' }
  ];

  ngOnInit(): void {
    this.loadStats();
    this.loadNormas();
  }

  loadStats(): void {
    this.http.get<LibStats>(this.apiUrl + '/stats').subscribe({
      next: s => this.stats.set(s),
      error: () => {}
    });
  }

  loadNormas(): void {
    this.http.get<Norma[]>(this.apiUrl + '/normas').subscribe({
      next: n => this.normas.set(n),
      error: () => {}
    });
  }

  search(): void {
    if (!this.searchQuery.trim()) return;
    this.isSearching.set(true);
    this.hasSearched.set(true);

    const params: any = { q: this.searchQuery };
    if (this.selectedArea) params.area = this.selectedArea;
    if (this.selectedTipo) params.tipo = this.selectedTipo;

    this.http.get<SearchResult[]>(this.apiUrl + '/search', { params }).subscribe({
      next: r => { this.results.set(r); this.isSearching.set(false); this.view.set('search'); },
      error: () => { this.isSearching.set(false); }
    });
  }

  openNorma(id: string): void {
    this.http.get(this.apiUrl + '/norma/' + id).subscribe({
      next: n => { this.selectedNorma.set(n); this.view.set('detail'); },
      error: () => {}
    });
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter') this.search();
  }

  getAreaColor(area: string): string {
    const colors: Record<string, string> = {
      'civil':          '#1a5296',
      'penal':          '#c0392b',
      'laboral':        '#1a6b3c',
      'constitucional': '#6c3483',
      'familiar':       '#c4922a',
      'administrativo': '#2e86ab'
    };
    return colors[area] || '#7a7268';
  }

  getTipoIcon(tipo: string): string {
    const icons: Record<string, string> = {
      'constitucion': '🏛',
      'codigo':       '📚',
      'ley':          '📋',
      'decreto':      '📜',
      'sentencia':    '⚖'
    };
    return icons[tipo] || '📄';
  }

  getObjectKeys(obj: Record<string, number>): string[] {
    return obj ? Object.keys(obj) : [];
  }

  back(): void {
    this.view.set('search');
    this.selectedNorma.set(null);
  }
}
'@)
OK "library.component.ts"

[System.IO.File]::WriteAllText("$fe\features\library\library.component.html", @'
<div class="lib-layout">

  <!-- Header -->
  <header class="page-header">
    <div>
      <h1 class="page-title">Biblioteca Legal Bolivia</h1>
      <p class="page-sub">
        @if (stats()) {
          {{ stats()!.total_normas }} normas · {{ stats()!.total_articulos_indexados }} articulos indexados
        } @else {
          CPE 2009 · Codigos · Leyes · Sentencias TCP
        }
      </p>
    </div>
    @if (view() === 'detail') {
      <button class="btn-ghost" (click)="back()">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14">
          <path stroke-linecap="round" stroke-linejoin="round" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
        </svg>
        Volver
      </button>
    }
  </header>

  <!-- Busqueda -->
  @if (view() !== 'detail') {
    <div class="search-bar">
      <div class="search-input-wrap">
        <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="16" height="16">
          <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
        </svg>
        <input
          class="search-input"
          [(ngModel)]="searchQuery"
          (keydown)="onKeydown($event)"
          placeholder="Buscar en normativa boliviana... ej: prescripcion, divorcio, despido, amparo">
      </div>
      <select class="filter-select" [(ngModel)]="selectedArea">
        @for (a of areas; track a.valor) {
          <option [value]="a.valor">{{ a.label }}</option>
        }
      </select>
      <select class="filter-select" [(ngModel)]="selectedTipo">
        @for (t of tipos; track t.valor) {
          <option [value]="t.valor">{{ t.label }}</option>
        }
      </select>
      <button class="btn-search" (click)="search()" [disabled]="isSearching() || !searchQuery.trim()">
        @if (isSearching()) { Buscando... } @else { Buscar }
      </button>
    </div>
  }

  <!-- Contenido principal -->
  <div class="main-area">

    <!-- Vista de busqueda -->
    @if (view() === 'search') {

      <!-- Stats cards -->
      @if (!hasSearched() && stats()) {
        <div class="stats-section">
          <div class="stats-grid">
            @for (area of getObjectKeys(stats()!.por_area); track area) {
              <div class="stat-card" (click)="selectedArea = area; search()">
                <span class="stat-icon">{{ getTipoIcon('codigo') }}</span>
                <div>
                  <p class="stat-num">{{ stats()!.por_area[area] }}</p>
                  <p class="stat-label">{{ area | titlecase }}</p>
                </div>
              </div>
            }
          </div>

          <div class="normas-section">
            <h3 class="section-title">Normas disponibles</h3>
            <div class="normas-list">
              @for (norma of normas(); track norma.id) {
                <div class="norma-row" (click)="openNorma(norma.id)">
                  <span class="norma-icon">{{ getTipoIcon(norma.tipo) }}</span>
                  <div class="norma-info">
                    <p class="norma-titulo">{{ norma.titulo }}</p>
                    <p class="norma-meta">
                      <span class="area-badge" [style.background]="getAreaColor(norma.area) + '18'" [style.color]="getAreaColor(norma.area)">{{ norma.area }}</span>
                      · {{ norma.total_articulos }} articulos · {{ norma.fecha | date:'yyyy' }}
                    </p>
                  </div>
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14" style="color:var(--txt-3);flex-shrink:0">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/>
                  </svg>
                </div>
              }
            </div>
          </div>
        </div>
      }

      <!-- Resultados de busqueda -->
      @if (hasSearched()) {
        <div class="results-section">
          @if (isSearching()) {
            <div class="searching-state">
              <div class="search-spinner"></div>
              <p>Buscando en normativa boliviana...</p>
            </div>
          } @else if (results().length === 0) {
            <div class="no-results">
              <p class="no-results-icon">🔍</p>
              <p>No se encontraron resultados para "<strong>{{ searchQuery }}</strong>"</p>
              <p class="no-results-hint">Intenta con otros terminos: prescripcion, contrato, despido, amparo, divorcio...</p>
            </div>
          } @else {
            <p class="results-count">{{ results().length }} resultado(s) para "{{ searchQuery }}"</p>
            <div class="results-list">
              @for (result of results(); track result.id) {
                <div class="result-card" (click)="openNorma(result.id)">
                  <div class="result-header">
                    <span class="result-icon">{{ getTipoIcon(result.tipo) }}</span>
                    <div class="result-info">
                      <h3 class="result-titulo">{{ result.titulo }}</h3>
                      <div class="result-meta">
                        <span class="area-badge" [style.background]="getAreaColor(result.area) + '18'" [style.color]="getAreaColor(result.area)">{{ result.area }}</span>
                        <span class="tipo-badge">{{ result.tipo }}</span>
                      </div>
                    </div>
                  </div>
                  <p class="result-resumen">{{ result.resumen }}</p>
                  @if (result.articulos_relevantes.length > 0) {
                    <div class="articulos-preview">
                      <p class="articulos-label">Articulos relevantes:</p>
                      @for (art of result.articulos_relevantes; track art.numero) {
                        <div class="articulo-chip">
                          <strong>Art. {{ art.numero }}</strong> — {{ art.texto.substring(0, 120) }}...
                        </div>
                      }
                    </div>
                  }
                </div>
              }
            </div>
          }
        </div>
      }
    }

    <!-- Detalle de norma -->
    @if (view() === 'detail' && selectedNorma()) {
      <div class="detail-section">
        <div class="detail-header">
          <span class="detail-icon">{{ getTipoIcon(selectedNorma().tipo) }}</span>
          <div>
            <h2 class="detail-titulo">{{ selectedNorma().titulo }}</h2>
            <div class="detail-meta">
              <span class="area-badge" [style.background]="getAreaColor(selectedNorma().area) + '18'" [style.color]="getAreaColor(selectedNorma().area)">{{ selectedNorma().area }}</span>
              <span>{{ selectedNorma().fecha | date:'dd/MM/yyyy' }}</span>
              <span>{{ selectedNorma().fuente }}</span>
            </div>
          </div>
        </div>

        <div class="detail-resumen">
          <h3>Descripcion</h3>
          <p>{{ selectedNorma().resumen }}</p>
        </div>

        <div class="detail-articulos">
          <h3>Articulos indexados</h3>
          <div class="articulos-list">
            @for (art of selectedNorma().articulos; track art.num) {
              <div class="articulo-card">
                <div class="articulo-num">Art. {{ art.num }}</div>
                <p class="articulo-texto">{{ art.texto }}</p>
              </div>
            }
          </div>
        </div>
      </div>
    }

  </div>
</div>
'@)

[System.IO.File]::WriteAllText("$fe\features\library\library.component.scss", @'
:host { display:flex; flex-direction:column; height:100vh; overflow:hidden; }
.lib-layout { display:flex; flex-direction:column; height:100vh; overflow:hidden; background:var(--bg); }

.page-header {
  display:flex; align-items:center; justify-content:space-between;
  padding:16px 24px; background:var(--surf); border-bottom:1px solid var(--bord); flex-shrink:0;
}
.page-title { font-family:"Playfair Display",serif; font-size:1.1rem; font-weight:600; color:var(--txt); }
.page-sub { font-size:.72rem; color:var(--txt-3); margin-top:2px; }

.btn-ghost {
  display:flex; align-items:center; gap:6px; background:none; border:1px solid var(--bord);
  color:var(--txt-2); font-size:.78rem; padding:6px 12px; border-radius:8px; cursor:pointer;
  font-family:'DM Sans',sans-serif; transition:.15s;
  &:hover { background:var(--surf-2); color:var(--txt); }
}

/* Search bar */
.search-bar {
  display:flex; gap:8px; padding:14px 24px;
  background:var(--surf); border-bottom:1px solid var(--bord); flex-shrink:0; flex-wrap:wrap;
}

.search-input-wrap {
  flex:1; display:flex; align-items:center; gap:8px;
  background:var(--bg); border:1.5px solid var(--bord); border-radius:10px; padding:9px 14px;
  min-width:200px; transition:.2s;
  &:focus-within { border-color:var(--prim-3); background:white; }
}
.search-icon { color:var(--txt-3); flex-shrink:0; }
.search-input { flex:1; border:none; background:none; font-size:.85rem; font-family:'DM Sans',sans-serif; color:var(--txt); outline:none; &::placeholder { color:var(--txt-3); } }

.filter-select {
  border:1px solid var(--bord); border-radius:8px; padding:8px 12px; font-size:.78rem;
  font-family:'DM Sans',sans-serif; color:var(--txt-2); background:var(--surf); cursor:pointer;
  outline:none; transition:.15s; &:focus { border-color:var(--prim-3); }
}

.btn-search {
  background:var(--prim); color:white; border:none; border-radius:8px; padding:8px 20px;
  font-size:.82rem; font-family:'DM Sans',sans-serif; cursor:pointer; transition:.15s; white-space:nowrap;
  &:hover:not(:disabled) { background:var(--prim-2); }
  &:disabled { opacity:.5; cursor:not-allowed; }
}

/* Main area */
.main-area { flex:1; overflow-y:auto; padding:20px 24px; }

/* Stats */
.stats-grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(140px, 1fr)); gap:8px; margin-bottom:24px; }
.stat-card {
  display:flex; align-items:center; gap:10px; background:var(--surf); border:1px solid var(--bord);
  border-radius:10px; padding:12px 14px; cursor:pointer; transition:.15s;
  &:hover { border-color:var(--prim-3); box-shadow:var(--shadow); }
}
.stat-icon { font-size:1.3rem; }
.stat-num { font-size:1.1rem; font-weight:600; color:var(--prim); line-height:1; }
.stat-label { font-size:.72rem; color:var(--txt-3); margin-top:2px; text-transform:capitalize; }

.normas-section { }
.section-title { font-family:"Playfair Display",serif; font-size:.95rem; font-weight:600; color:var(--txt); margin-bottom:12px; }
.normas-list { display:flex; flex-direction:column; gap:6px; }
.norma-row {
  display:flex; align-items:center; gap:12px; background:var(--surf); border:1px solid var(--bord);
  border-radius:10px; padding:12px 16px; cursor:pointer; transition:.15s;
  &:hover { border-color:var(--prim-3); box-shadow:var(--shadow); }
}
.norma-icon { font-size:1.3rem; flex-shrink:0; }
.norma-info { flex:1; }
.norma-titulo { font-size:.85rem; font-weight:500; color:var(--txt); margin-bottom:4px; }
.norma-meta { font-size:.72rem; color:var(--txt-3); display:flex; align-items:center; gap:6px; }

/* Badges */
.area-badge { padding:2px 8px; border-radius:20px; font-size:.7rem; font-weight:500; }
.tipo-badge { background:var(--surf-2); color:var(--txt-3); padding:2px 8px; border-radius:20px; font-size:.7rem; }

/* Results */
.results-count { font-size:.78rem; color:var(--txt-3); margin-bottom:12px; }
.results-list { display:flex; flex-direction:column; gap:10px; }
.result-card {
  background:var(--surf); border:1px solid var(--bord); border-radius:12px; padding:16px;
  cursor:pointer; transition:.15s;
  &:hover { border-color:var(--prim-3); box-shadow:var(--shadow-md); }
}
.result-header { display:flex; gap:12px; align-items:flex-start; margin-bottom:8px; }
.result-icon { font-size:1.4rem; flex-shrink:0; }
.result-info { flex:1; }
.result-titulo { font-size:.9rem; font-weight:500; color:var(--txt); margin-bottom:5px; }
.result-meta { display:flex; gap:6px; flex-wrap:wrap; }
.result-resumen { font-size:.8rem; color:var(--txt-2); line-height:1.5; margin-bottom:10px; }

.articulos-preview { background:var(--surf-2); border-radius:8px; padding:10px 12px; }
.articulos-label { font-size:.72rem; font-weight:500; color:var(--txt-3); margin-bottom:6px; text-transform:uppercase; letter-spacing:.04em; }
.articulo-chip { font-size:.78rem; color:var(--txt-2); padding:5px 0; border-bottom:1px solid var(--bord); &:last-child { border:none; } strong { color:var(--prim); } }

/* States */
.searching-state, .no-results { display:flex; flex-direction:column; align-items:center; justify-content:center; padding:48px; gap:12px; text-align:center; }
.search-spinner { width:32px; height:32px; border:2px solid var(--bord); border-top-color:var(--prim); border-radius:50%; animation:spin .8s linear infinite; }
@keyframes spin { to { transform:rotate(360deg); } }
.no-results-icon { font-size:2rem; }
.no-results-hint { font-size:.78rem; color:var(--txt-3); max-width:360px; }

/* Detail */
.detail-section { max-width:800px; }
.detail-header { display:flex; gap:14px; align-items:flex-start; margin-bottom:20px; padding-bottom:16px; border-bottom:1px solid var(--bord); }
.detail-icon { font-size:2rem; flex-shrink:0; }
.detail-titulo { font-family:"Playfair Display",serif; font-size:1.1rem; font-weight:600; color:var(--txt); margin-bottom:8px; }
.detail-meta { display:flex; gap:8px; flex-wrap:wrap; align-items:center; font-size:.75rem; color:var(--txt-3); }

.detail-resumen { background:var(--surf); border:1px solid var(--bord); border-radius:10px; padding:16px; margin-bottom:20px;
  h3 { font-size:.82rem; font-weight:500; color:var(--txt-2); margin-bottom:8px; text-transform:uppercase; letter-spacing:.04em; }
  p { font-size:.85rem; color:var(--txt-2); line-height:1.6; }
}

.detail-articulos {
  h3 { font-family:"Playfair Display",serif; font-size:.95rem; font-weight:600; color:var(--txt); margin-bottom:12px; }
}
.articulos-list { display:flex; flex-direction:column; gap:8px; }
.articulo-card { background:var(--surf); border:1px solid var(--bord); border-radius:8px; padding:12px 16px; }
.articulo-num { font-size:.75rem; font-weight:600; color:var(--prim); margin-bottom:5px; font-family:'DM Mono',monospace; }
.articulo-texto { font-size:.83rem; color:var(--txt-2); line-height:1.6; }
'@)
OK "library.component (HTML + SCSS)"

# ══════════════════════════════════════════════════════
# RESUMEN FINAL
# ══════════════════════════════════════════════════════
Set-Location $Ruta
Write-Host @"

===============================================================
  Biblioteca Legal Bolivia - instalada
===============================================================

  INCLUYE:
  - 8 normas bolivianas fundamentales con articulos clave:
    * CPE 2009 (10 articulos)
    * Codigo Civil Ley 12760 (8 articulos)
    * Codigo Penal Ley 1768 (7 articulos)
    * Ley 603 Familias (8 articulos)
    * CPC Ley 439 (6 articulos)
    * CPP Ley 1970 (6 articulos)
    * Ley General del Trabajo (6 articulos)
    * Ley 2341 Procedimiento Administrativo (3 articulos)

  - Busqueda por palabras clave con scoring de relevancia
  - Filtros por area legal y tipo de norma
  - Vista detallada de cada norma con sus articulos
  - Intentos de scraping de Gaceta Oficial y TCP

  REINICIAR BACKEND para cargar la nueva ruta:
  Ctrl+C en la terminal del backend, luego:
  uvicorn api.main:app --reload --port 8001

  Abrir: http://localhost:4200/library

===============================================================
"@ -ForegroundColor Green
