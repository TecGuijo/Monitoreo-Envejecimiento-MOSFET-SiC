# Monitoreo del envejecimiento de un MOSFET de SiC

Este repositorio contiene los códigos desarrollados en MATLAB y Python como parte del trabajo de tesis de maestría relacionado con el monitoreo y la determinación del estado de envejecimiento de dispositivos de potencia de carburo de silicio (SiC).

## Descripción

Los códigos implementados permiten realizar la adquisición y procesamiento de datos experimentales obtenidos durante un ensayo de envejecimiento acelerado de un MOSFET de potencia de SiC.

El procedimiento comprende la adquisición de señales, el postprocesamiento de los datos, la separación de las diferentes etapas de envejecimiento, la obtención del voltaje de umbral dinámico, la generación de conjuntos de datos y la clasificación del estado de envejecimiento mediante algoritmos K-Nearest Neighbors (KNN).

## Flujo de procesamiento

Los códigos deben ejecutarse en el siguiente orden:

1. `1_Aquisicion_de_datos.m`
2. `2_Post_procesamiento.m`
3. `3_Generacion_etapas.m`
4. `4_Obtencion_vth.m`
5. `5_Generar_DATAset_Train.m`
6. `6_Generar_DATAset_Prueba.m`
7. `7_KNN_Fusión.py`

---

## Descripción de los códigos

### 1. Adquisición de datos

**Archivo:** `1_Aquisicion_de_datos.m`

Realiza la adquisición y almacenamiento de las señales experimentales obtenidas durante el ensayo de envejecimiento.

---

### 2. Postprocesamiento

**Archivo:** `2_Post_procesamiento.m`

Realiza el procesamiento de las señales adquiridas y organiza la información necesaria para la extracción posterior de los indicadores de salud.

---

### 3. Generación de etapas

**Archivo:** `3_Generacion_etapas.m`

Organiza los datos experimentales y los divide en las diferentes etapas de envejecimiento definidas para el análisis del dispositivo.

---

### 4. Obtención del voltaje de umbral

**Archivo:** `4_Obtencion_vth.m`

Obtiene el voltaje de umbral dinámico del MOSFET de SiC a partir del comportamiento de las señales de voltaje compuerta-fuente, \(V_{GS}\), y corriente de drenaje, \(I_D\), durante el transitorio de encendido.

---

### 5. Generación del conjunto de entrenamiento

**Archivo:** `5_Generar_DATAset_Train.m`

Genera el conjunto de datos utilizado para el entrenamiento de los clasificadores KNN a partir de los indicadores de salud obtenidos durante el ensayo.

---

### 6. Generación del conjunto de prueba

**Archivo:** `6_Generar_DATAset_Prueba.m`

Genera el conjunto de datos independiente utilizado para evaluar el desempeño de los clasificadores desarrollados.

---

### 7. Clasificador KNN por fusión

**Archivo:** `7_KNN_Fusión.py`

Implementa los clasificadores K-Nearest Neighbors utilizados para determinar el estado de envejecimiento del dispositivo.

El algoritmo utiliza diferentes indicadores de salud y combina las salidas de los clasificadores individuales mediante una estrategia de fusión para obtener el estado final de envejecimiento.

---

## Indicadores de salud

Los principales indicadores utilizados para el monitoreo del estado de envejecimiento son:

- Resistencia en conducción, \(R_{DS(on)}\).
- Voltaje de umbral, \(V_{th}\).
- Temperatura de unión estimada, \(T_j\).

Estos parámetros son utilizados posteriormente por los clasificadores para determinar el estado de envejecimiento del MOSFET de SiC.

## Software utilizado

- MATLAB
- Python 3

## Requisitos

Para ejecutar correctamente los códigos se requiere:

- MATLAB.
- Python 3.
- Bibliotecas de Python utilizadas por el clasificador KNN.
- Datos experimentales obtenidos durante el ensayo de envejecimiento.

## Trabajo de tesis

**Diseño de una metodología para determinar el estado de envejecimiento de dispositivos de potencia en aplicaciones de inversores para vehículos eléctricos.**

## Autor

**Juan Guillermo Tejeda Cortez**

Maestría en Ingeniería Electrónica  
[Benemérita Universidad Autónoma de Puebla]

## Uso académico

Este repositorio contiene los códigos desarrollados como parte del trabajo de tesis mencionado anteriormente.

En caso de utilizar total o parcialmente los códigos o la metodología presentada en este repositorio para trabajos académicos, se solicita citar la tesis y las publicaciones asociadas al proyecto.
