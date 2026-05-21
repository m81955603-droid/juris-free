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