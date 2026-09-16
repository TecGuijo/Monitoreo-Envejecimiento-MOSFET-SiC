import os
import pandas as pd
import customtkinter as ctk
from tkinter import filedialog, messagebox, ttk

from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score, confusion_matrix, classification_report

# =========================================================
# CONFIGURACIÓN GENERAL
# =========================================================
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

CATEGORIES = {
    1: "Sano",
    2: "Degradación inicial",
    3: "Degradación severa",
    4: "Falla"
}

FUSE_METHOD = "max"

# =========================================================
# MEJOR CONFIGURACIÓN KNN POR FUSIÓN
# =========================================================
KNN_K = 9
KNN_METRIC = "euclidean"
KNN_WEIGHTS = "uniform"

train_path = ""
predict_path = ""
results_df = None

validation_enabled = False

validation_accuracy_exacta = None
validation_accuracy_tolerancia = None

validation_accuracy_rdson = None
validation_accuracy_vth = None
validation_accuracy_tj = None

# =========================================================
# COLORES
# =========================================================
BG_MAIN     = "#071119"
BG_CARD     = "#0B1B26"
BG_CARD_2   = "#102634"
TEXT_MAIN   = "#D9F7FF"
TEXT_SOFT   = "#7FA6B8"
ACCENT_CYAN = "#00E5FF"
ACCENT_TEAL = "#00FFC6"
ACCENT_ORNG = "#FF9F1C"
ACCENT_BLUE = "#1F6FEB"
BORDER_COL  = "#123B52"

# =========================================================
# FUNCIONES BASE
# =========================================================
def fuse_categories(c_r, c_v, c_t, method="max"):
    if method == "max":
        return int(max(c_r, c_v, c_t))
    raise ValueError("Método de fusión no soportado")

def read_csv_robust(file_path):
    """
    Lee CSV con separador coma o punto y coma.
    """
    try:
        df = pd.read_csv(file_path)
    except Exception:
        df = pd.read_csv(file_path, sep=";")

    if len(df.columns) == 1:
        df = pd.read_csv(file_path, sep=";")

    return df

def normalize_columns(df):
    """
    Normaliza nombres de columnas al formato interno:
        rdson, vth, tj, cat_rdson, cat_vth, cat_tj
    """

    df.columns = df.columns.str.strip()

    rename_map = {
        # Valores RDS(on)
        "valorRDSon": "rdson",
        "ValorRDSon": "rdson",
        "RDSon": "rdson",
        "RDS(on)": "rdson",
        "rdson": "rdson",

        # Valores Vth
        "valorVth": "vth",
        "ValorVth": "vth",
        "Vth": "vth",
        "vth": "vth",

        # Valores Tj
        "valorTj": "tj",
        "ValorTj": "tj",
        "Tj": "tj",
        "tj": "tj",

        # Clasificación RDS(on)
        "etapaRDSon": "cat_rdson",
        "EtapaRDSon": "cat_rdson",
        "clasificacionRDSon": "cat_rdson",
        "ClasificacionRDSon": "cat_rdson",
        "clasificaciónRDSon": "cat_rdson",
        "ClasificaciónRDSon": "cat_rdson",
        "cat_rdson": "cat_rdson",

        # Clasificación Vth
        "etapaVth": "cat_vth",
        "EtapaVth": "cat_vth",
        "clasificacionVth": "cat_vth",
        "ClasificacionVth": "cat_vth",
        "clasificaciónVth": "cat_vth",
        "ClasificaciónVth": "cat_vth",
        "cat_vth": "cat_vth",

        # Clasificación Tj
        "etapaTj": "cat_tj",
        "EtapaTj": "cat_tj",
        "clasificacionTj": "cat_tj",
        "ClasificacionTj": "cat_tj",
        "clasificaciónTj": "cat_tj",
        "ClasificaciónTj": "cat_tj",
        "cat_tj": "cat_tj"
    }

    df = df.rename(columns=rename_map)
    return df

def clean_numeric_columns(df, cols):
    """
    Convierte columnas a numérico y elimina filas inválidas.
    """
    for col in cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=cols).reset_index(drop=True)
    return df

def validate_categories(df, cols, dataset_name):
    """
    Verifica que las categorías estén entre 1 y 4.
    """
    valid_classes = set(CATEGORIES.keys())

    for col in cols:
        unique_values = set(df[col].dropna().astype(int).unique())
        invalid = unique_values - valid_classes

        if invalid:
            raise ValueError(
                f"El archivo {dataset_name} tiene clasificaciones inválidas en la columna {col}:\n\n"
                f"{sorted(invalid)}\n\n"
                f"Solo se permiten: {sorted(valid_classes)}"
            )

def detect_validation_columns(df):
    return {"cat_rdson", "cat_vth", "cat_tj"}.issubset(df.columns)

def build_knn_1d():
    """
    Construye un KNN 1D usando la mejor configuración encontrada.
    """
    return Pipeline([
        ("scaler", StandardScaler()),
        ("knn", KNeighborsClassifier(
            n_neighbors=KNN_K,
            metric=KNN_METRIC,
            weights=KNN_WEIGHTS
        ))
    ])

# =========================================================
# PREDICCIÓN KNN POR FUSIÓN
# =========================================================
def run_prediction(train_file, predict_file):
    global validation_enabled

    global validation_accuracy_exacta
    global validation_accuracy_tolerancia

    global validation_accuracy_rdson
    global validation_accuracy_vth
    global validation_accuracy_tj

    validation_enabled = False

    validation_accuracy_exacta = None
    validation_accuracy_tolerancia = None

    validation_accuracy_rdson = None
    validation_accuracy_vth = None
    validation_accuracy_tj = None

    print("\n====================================")
    print("ARCHIVOS USADOS")
    print("====================================")
    print("Train:  ", train_file)
    print("Predict:", predict_file)
    print("====================================\n")

    train_df = read_csv_robust(train_file)
    predict_df = read_csv_robust(predict_file)

    train_df = normalize_columns(train_df)
    predict_df = normalize_columns(predict_df)

    required_train_cols = {
        "rdson", "vth", "tj",
        "cat_rdson", "cat_vth", "cat_tj"
    }

    required_predict_cols = {
        "rdson", "vth", "tj"
    }

    if not required_train_cols.issubset(train_df.columns):
        raise ValueError(
            "El archivo de entrenamiento debe contener:\n\n"
            "valorRDSon, clasificacionRDSon,\n"
            "valorVth, clasificacionVth,\n"
            "valorTj, clasificacionTj\n\n"
            "También acepta etapaRDSon, etapaVth y etapaTj."
        )

    if not required_predict_cols.issubset(predict_df.columns):
        raise ValueError(
            "El archivo de prueba debe contener:\n\n"
            "valorRDSon, valorVth, valorTj\n\n"
            "Opcionalmente, para validación:\n"
            "clasificacionRDSon, clasificacionVth, clasificacionTj"
        )

    validation_enabled = detect_validation_columns(predict_df)

    # =====================================================
    # LIMPIEZA DE ENTRENAMIENTO
    # =====================================================
    train_df = clean_numeric_columns(
        train_df,
        ["rdson", "vth", "tj", "cat_rdson", "cat_vth", "cat_tj"]
    )

    train_df["cat_rdson"] = train_df["cat_rdson"].astype(int)
    train_df["cat_vth"] = train_df["cat_vth"].astype(int)
    train_df["cat_tj"] = train_df["cat_tj"].astype(int)

    validate_categories(
        train_df,
        ["cat_rdson", "cat_vth", "cat_tj"],
        "de entrenamiento"
    )

    train_df["cat_global"] = train_df.apply(
        lambda row: fuse_categories(
            int(row["cat_rdson"]),
            int(row["cat_vth"]),
            int(row["cat_tj"]),
            FUSE_METHOD
        ),
        axis=1
    )

    # =====================================================
    # LIMPIEZA DE PRUEBA
    # =====================================================
    if validation_enabled:
        predict_df = clean_numeric_columns(
            predict_df,
            ["rdson", "vth", "tj", "cat_rdson", "cat_vth", "cat_tj"]
        )

        predict_df["cat_rdson"] = predict_df["cat_rdson"].astype(int)
        predict_df["cat_vth"] = predict_df["cat_vth"].astype(int)
        predict_df["cat_tj"] = predict_df["cat_tj"].astype(int)

        validate_categories(
            predict_df,
            ["cat_rdson", "cat_vth", "cat_tj"],
            "de prueba"
        )

        predict_df["cat_global"] = predict_df.apply(
            lambda row: fuse_categories(
                int(row["cat_rdson"]),
                int(row["cat_vth"]),
                int(row["cat_tj"]),
                FUSE_METHOD
            ),
            axis=1
        )

    else:
        predict_df = clean_numeric_columns(
            predict_df,
            ["rdson", "vth", "tj"]
        )

    if len(train_df) < KNN_K:
        raise ValueError(
            f"El dataset de entrenamiento tiene {len(train_df)} filas válidas, "
            f"pero K = {KNN_K}. Necesitas al menos {KNN_K} filas válidas."
        )

    if len(predict_df) == 0:
        raise ValueError("El archivo de prueba no tiene filas válidas.")

    print("\n====================================")
    print("DISTRIBUCIÓN DE CLASES")
    print("====================================")
    print("Entrenamiento global:")
    print(train_df["cat_global"].value_counts().sort_index())

    if validation_enabled:
        print("\nPrueba global:")
        print(predict_df["cat_global"].value_counts().sort_index())

    print("====================================\n")

    # =====================================================
    # ENTRENAR LOS 3 KNN INDEPENDIENTES
    # =====================================================
    model_r = build_knn_1d()
    model_v = build_knn_1d()
    model_t = build_knn_1d()

    model_r.fit(train_df[["rdson"]], train_df["cat_rdson"])
    model_v.fit(train_df[["vth"]], train_df["cat_vth"])
    model_t.fit(train_df[["tj"]], train_df["cat_tj"])

    # =====================================================
    # PREDICCIÓN FINAL
    # =====================================================
    results = []

    y_true_global = []
    y_pred_global = []

    y_true_r = []
    y_pred_r = []

    y_true_v = []
    y_pred_v = []

    y_true_t = []
    y_pred_t = []

    for _, row in predict_df.iterrows():
        rdson = row["rdson"]
        vth = row["vth"]
        tj = row["tj"]

        c_r = int(model_r.predict(pd.DataFrame([[rdson]], columns=["rdson"]))[0])
        c_v = int(model_v.predict(pd.DataFrame([[vth]], columns=["vth"]))[0])
        c_t = int(model_t.predict(pd.DataFrame([[tj]], columns=["tj"]))[0])

        c_global = fuse_categories(c_r, c_v, c_t, FUSE_METHOD)

        if validation_enabled:
            real_r = int(row["cat_rdson"])
            real_v = int(row["cat_vth"])
            real_t = int(row["cat_tj"])

            real_global = fuse_categories(real_r, real_v, real_t, FUSE_METHOD)

            acierto_r = int(c_r == real_r)
            acierto_v = int(c_v == real_v)
            acierto_t = int(c_t == real_t)

            acierto_global = int(c_global == real_global)
            acierto_tolerancia = int(abs(c_global - real_global) <= 1)

            y_true_global.append(real_global)
            y_pred_global.append(c_global)

            y_true_r.append(real_r)
            y_pred_r.append(c_r)

            y_true_v.append(real_v)
            y_pred_v.append(c_v)

            y_true_t.append(real_t)
            y_pred_t.append(c_t)

            results.append([
                rdson,
                c_r,
                CATEGORIES.get(c_r, "Desconocido"),
                real_r,
                CATEGORIES.get(real_r, "Desconocido"),
                acierto_r,

                vth,
                c_v,
                CATEGORIES.get(c_v, "Desconocido"),
                real_v,
                CATEGORIES.get(real_v, "Desconocido"),
                acierto_v,

                tj,
                c_t,
                CATEGORIES.get(c_t, "Desconocido"),
                real_t,
                CATEGORIES.get(real_t, "Desconocido"),
                acierto_t,

                c_global,
                CATEGORIES.get(c_global, "Desconocido"),

                real_global,
                CATEGORIES.get(real_global, "Desconocido"),

                acierto_global,
                acierto_tolerancia
            ])

        else:
            results.append([
                rdson,
                c_r,
                CATEGORIES.get(c_r, "Desconocido"),

                vth,
                c_v,
                CATEGORIES.get(c_v, "Desconocido"),

                tj,
                c_t,
                CATEGORIES.get(c_t, "Desconocido"),

                c_global,
                CATEGORIES.get(c_global, "Desconocido")
            ])

    # =====================================================
    # MÉTRICAS
    # =====================================================
    if validation_enabled:
        validation_accuracy_exacta = accuracy_score(y_true_global, y_pred_global)

        aciertos_tolerancia = [
            int(abs(pred - real) <= 1)
            for pred, real in zip(y_pred_global, y_true_global)
        ]

        validation_accuracy_tolerancia = sum(aciertos_tolerancia) / len(aciertos_tolerancia)

        validation_accuracy_rdson = accuracy_score(y_true_r, y_pred_r)
        validation_accuracy_vth = accuracy_score(y_true_v, y_pred_v)
        validation_accuracy_tj = accuracy_score(y_true_t, y_pred_t)

        print("\n====================================")
        print("VALIDACIÓN FINAL KNN POR FUSIÓN")
        print("====================================")
        print(f"K:                         {KNN_K}")
        print(f"Distancia:                 {KNN_METRIC}")
        print(f"Weights:                   {KNN_WEIGHTS}")
        print(f"Precisión exacta global:   {validation_accuracy_exacta * 100:.2f}%")
        print(f"Precisión tolerancia:      {validation_accuracy_tolerancia * 100:.2f}%")
        print("------------------------------------")
        print(f"Precisión RDS(on):         {validation_accuracy_rdson * 100:.2f}%")
        print(f"Precisión Vth:             {validation_accuracy_vth * 100:.2f}%")
        print(f"Precisión Tj:              {validation_accuracy_tj * 100:.2f}%")
        print("------------------------------------")
        print("Matriz de confusión global:")
        print(confusion_matrix(y_true_global, y_pred_global, labels=[1, 2, 3, 4]))
        print("------------------------------------")
        print("Reporte de clasificación global:")
        print(classification_report(
            y_true_global,
            y_pred_global,
            labels=[1, 2, 3, 4],
            target_names=[
                "Sano",
                "Deg. inicial",
                "Deg. severa",
                "Falla"
            ],
            zero_division=0
        ))
        print("====================================\n")

        return pd.DataFrame(results, columns=[
            "rdson", "cat_rdson", "estado_rdson", "cat_real_rdson", "estado_real_rdson", "acierto_rdson",
            "vth", "cat_vth", "estado_vth", "cat_real_vth", "estado_real_vth", "acierto_vth",
            "tj", "cat_tj", "estado_tj", "cat_real_tj", "estado_real_tj", "acierto_tj",
            "cat_global", "estado_global",
            "cat_real_global", "estado_real_global",
            "acierto_global", "acierto_tolerancia"
        ])

    else:
        return pd.DataFrame(results, columns=[
            "rdson", "cat_rdson", "estado_rdson",
            "vth", "cat_vth", "estado_vth",
            "tj", "cat_tj", "estado_tj",
            "cat_global", "estado_global"
        ])

# =========================================================
# FUNCIONES DE INTERFAZ
# =========================================================
def select_train_file():
    global train_path

    path = filedialog.askopenfilename(
        title="Seleccionar dataset de entrenamiento",
        filetypes=[("CSV files", "*.csv")]
    )

    if path:
        train_path = path
        train_value.configure(text=os.path.basename(path))

def select_predict_file():
    global predict_path

    path = filedialog.askopenfilename(
        title="Seleccionar dataset de prueba",
        filetypes=[("CSV files", "*.csv")]
    )

    if path:
        predict_path = path
        predict_value.configure(text=os.path.basename(path))

def update_summary(df):
    conteo = df["cat_global"].value_counts().sort_index()

    total_value.configure(text=str(len(df)))
    sano_value.configure(text=str(conteo.get(1, 0)))
    inicial_value.configure(text=str(conteo.get(2, 0)))
    severa_value.configure(text=str(conteo.get(3, 0)))
    falla_value.configure(text=str(conteo.get(4, 0)))

    resumen_box.configure(state="normal")
    resumen_box.delete("1.0", "end")

    resumen_box.insert("end", f"Sano: {conteo.get(1, 0)}\n")
    resumen_box.insert("end", f"Degradación inicial: {conteo.get(2, 0)}\n")
    resumen_box.insert("end", f"Degradación severa: {conteo.get(3, 0)}\n")
    resumen_box.insert("end", f"Falla: {conteo.get(4, 0)}")

    resumen_box.insert("end", "\n\n")
    resumen_box.insert("end", "CONFIGURACIÓN KNN FUSIÓN\n")
    resumen_box.insert("end", f"K: {KNN_K}\n")
    resumen_box.insert("end", f"Distancia: {KNN_METRIC}\n")
    resumen_box.insert("end", f"Weights: {KNN_WEIGHTS}\n")

    if validation_enabled and validation_accuracy_exacta is not None:
        resumen_box.insert("end", "\nVALIDACIÓN GLOBAL\n")
        resumen_box.insert("end", f"Precisión exacta:     {validation_accuracy_exacta * 100:.2f}%\n")
        resumen_box.insert("end", f"Precisión tolerancia: {validation_accuracy_tolerancia * 100:.2f}%\n")

        resumen_box.insert("end", "\nVALIDACIÓN POR PARÁMETRO\n")
        resumen_box.insert("end", f"RDS(on): {validation_accuracy_rdson * 100:.2f}%\n")
        resumen_box.insert("end", f"Vth:     {validation_accuracy_vth * 100:.2f}%\n")
        resumen_box.insert("end", f"Tj:      {validation_accuracy_tj * 100:.2f}%")
    else:
        resumen_box.insert("end", "\nValidación: no disponible")

    resumen_box.configure(state="disabled")

def clear_table():
    for item in tree.get_children():
        tree.delete(item)

def configure_table_columns(df):
    old_cols = tree["columns"]

    for col in old_cols:
        tree.heading(col, text="")
        tree.column(col, width=0)

    cols = list(df.columns)
    tree["columns"] = cols

    headings = {
        "rdson": "RDS(on)",
        "cat_rdson": "Cat RDS",
        "estado_rdson": "Estado RDS",
        "cat_real_rdson": "Cat Real RDS",
        "estado_real_rdson": "Estado Real RDS",
        "acierto_rdson": "Acierto RDS",

        "vth": "Vth",
        "cat_vth": "Cat Vth",
        "estado_vth": "Estado Vth",
        "cat_real_vth": "Cat Real Vth",
        "estado_real_vth": "Estado Real Vth",
        "acierto_vth": "Acierto Vth",

        "tj": "Tj",
        "cat_tj": "Cat Tj",
        "estado_tj": "Estado Tj",
        "cat_real_tj": "Cat Real Tj",
        "estado_real_tj": "Estado Real Tj",
        "acierto_tj": "Acierto Tj",

        "cat_global": "Cat Global",
        "estado_global": "Estado Global",
        "cat_real_global": "Cat Real Global",
        "estado_real_global": "Estado Real Global",
        "acierto_global": "Acierto Global",
        "acierto_tolerancia": "Acierto ±1"
    }

    widths = {
        "rdson": 90,
        "cat_rdson": 75,
        "estado_rdson": 140,
        "cat_real_rdson": 100,
        "estado_real_rdson": 145,
        "acierto_rdson": 90,

        "vth": 90,
        "cat_vth": 75,
        "estado_vth": 140,
        "cat_real_vth": 100,
        "estado_real_vth": 145,
        "acierto_vth": 90,

        "tj": 90,
        "cat_tj": 75,
        "estado_tj": 140,
        "cat_real_tj": 100,
        "estado_real_tj": 145,
        "acierto_tj": 90,

        "cat_global": 95,
        "estado_global": 150,
        "cat_real_global": 120,
        "estado_real_global": 160,
        "acierto_global": 110,
        "acierto_tolerancia": 110
    }

    for col in cols:
        tree.heading(col, text=headings.get(col, col))
        tree.column(col, width=widths.get(col, 110), anchor="center")

def execute_prediction():
    global results_df

    if not train_path or not predict_path:
        messagebox.showwarning("Advertencia", "Debes seleccionar ambos archivos CSV.")
        return

    try:
        status_value.configure(text="Procesando...", text_color=ACCENT_ORNG)
        app.update_idletasks()

        results_df = run_prediction(train_path, predict_path)

        clear_table()
        configure_table_columns(results_df)

        for _, row in results_df.iterrows():
            estado_global = row["estado_global"]
            tag = "default"

            if estado_global == "Sano":
                tag = "sano"
            elif estado_global == "Degradación inicial":
                tag = "inicial"
            elif estado_global == "Degradación severa":
                tag = "severa"
            elif estado_global == "Falla":
                tag = "falla"

            tree.insert("", "end", values=list(row), tags=(tag,))

        update_summary(results_df)

        if validation_enabled:
            status_value.configure(text="Predicción + validación completadas", text_color=ACCENT_TEAL)

            messagebox.showinfo(
                "Éxito",
                "KNN por fusión completado correctamente.\n\n"
                f"K: {KNN_K}\n"
                f"Distancia: {KNN_METRIC}\n"
                f"Weights: {KNN_WEIGHTS}\n\n"
                f"Precisión exacta global: {validation_accuracy_exacta * 100:.2f}%\n"
                f"Precisión tolerancia: {validation_accuracy_tolerancia * 100:.2f}%\n\n"
                f"RDS(on): {validation_accuracy_rdson * 100:.2f}%\n"
                f"Vth: {validation_accuracy_vth * 100:.2f}%\n"
                f"Tj: {validation_accuracy_tj * 100:.2f}%"
            )
        else:
            status_value.configure(text="Predicción completada", text_color=ACCENT_TEAL)

            messagebox.showinfo(
                "Éxito",
                "KNN por fusión completado correctamente.\n\n"
                "El archivo de prueba no tenía clasificación, por eso no se hizo validación."
            )

    except Exception as e:
        status_value.configure(text="Error", text_color="#FF5A5F")
        messagebox.showerror("Error", str(e))

def save_results():
    global results_df

    if results_df is None:
        messagebox.showwarning("Advertencia", "Primero debes ejecutar la predicción.")
        return

    path = filedialog.asksaveasfilename(
        title="Guardar resultados",
        defaultextension=".csv",
        filetypes=[("CSV files", "*.csv")],
        initialfile="resultados_knn_fusion_k21_euclidean_uniform.csv"
    )

    if path:
        results_df.to_csv(path, index=False)
        messagebox.showinfo("Guardado", f"Resultados guardados en:\n{path}")

# =========================================================
# APP PRINCIPAL
# =========================================================
app = ctk.CTk()
app.title("Clasificador de envejecimiento de MOSFET de SiC mediante KNN por fusión")
app.geometry("1750x880")
app.configure(fg_color=BG_MAIN)

# =========================================================
# ENCABEZADO
# =========================================================
header = ctk.CTkFrame(app, fg_color=BG_MAIN, corner_radius=0)
header.pack(fill="x", padx=20, pady=(18, 8))

title_lbl = ctk.CTkLabel(
    header,
    text="CLASIFICADOR DE ENVEJECIMIENTO DE MOSFET DE SiC MEDIANTE KNN POR FUSIÓN",
    font=ctk.CTkFont(size=26, weight="bold"),
    text_color=TEXT_MAIN
)
title_lbl.pack(anchor="w")

# =========================================================
# CONTENEDOR SUPERIOR
# =========================================================
top_container = ctk.CTkFrame(app, fg_color=BG_MAIN)
top_container.pack(fill="x", padx=20, pady=(6, 6))

top_container.grid_columnconfigure((0, 1, 2, 3), weight=1)

# TRAIN
card_train = ctk.CTkFrame(
    top_container,
    fg_color=BG_CARD,
    corner_radius=18,
    border_width=1,
    border_color=BORDER_COL
)
card_train.grid(row=0, column=0, padx=8, pady=8, sticky="nsew")

ctk.CTkLabel(
    card_train,
    text="DATASET DE ENTRENAMIENTO",
    font=ctk.CTkFont(size=16, weight="bold"),
    text_color=ACCENT_CYAN
).pack(anchor="w", padx=16, pady=(16, 6))

train_value = ctk.CTkLabel(
    card_train,
    text="No seleccionado",
    text_color=TEXT_MAIN,
    wraplength=240,
    justify="left"
)
train_value.pack(anchor="w", padx=16, pady=(0, 12))

ctk.CTkButton(
    card_train,
    text="Seleccionar",
    command=select_train_file,
    fg_color=ACCENT_BLUE,
    hover_color="#174EA6"
).pack(padx=16, pady=(0, 16), fill="x")

# PREDICT
card_predict = ctk.CTkFrame(
    top_container,
    fg_color=BG_CARD,
    corner_radius=18,
    border_width=1,
    border_color=BORDER_COL
)
card_predict.grid(row=0, column=1, padx=8, pady=8, sticky="nsew")

ctk.CTkLabel(
    card_predict,
    text="DATASET DE PRUEBA",
    font=ctk.CTkFont(size=16, weight="bold"),
    text_color=ACCENT_TEAL
).pack(anchor="w", padx=16, pady=(16, 6))

predict_value = ctk.CTkLabel(
    card_predict,
    text="No seleccionado",
    text_color=TEXT_MAIN,
    wraplength=240,
    justify="left"
)
predict_value.pack(anchor="w", padx=16, pady=(0, 12))

ctk.CTkButton(
    card_predict,
    text="Seleccionar",
    command=select_predict_file,
    fg_color="#008F7A",
    hover_color="#006C5E"
).pack(padx=16, pady=(0, 16), fill="x")

# ACCIONES
card_actions = ctk.CTkFrame(
    top_container,
    fg_color=BG_CARD,
    corner_radius=18,
    border_width=1,
    border_color=BORDER_COL
)
card_actions.grid(row=0, column=2, padx=8, pady=8, sticky="nsew")

ctk.CTkLabel(
    card_actions,
    text="ACCIONES",
    font=ctk.CTkFont(size=16, weight="bold"),
    text_color=ACCENT_ORNG
).pack(anchor="w", padx=16, pady=(16, 10))

ctk.CTkButton(
    card_actions,
    text="Ejecutar KNN por fusión",
    command=execute_prediction,
    fg_color=ACCENT_ORNG,
    hover_color="#CC7A00",
    text_color="black"
).pack(padx=16, pady=(0, 10), fill="x")

ctk.CTkButton(
    card_actions,
    text="Guardar resultados",
    command=save_results,
    fg_color="#1B2A35",
    hover_color="#243847",
    border_width=1,
    border_color=ACCENT_CYAN
).pack(padx=16, pady=(0, 10), fill="x")

status_title = ctk.CTkLabel(
    card_actions,
    text="Estado",
    text_color=TEXT_SOFT
)
status_title.pack(anchor="w", padx=16, pady=(8, 0))

status_value = ctk.CTkLabel(
    card_actions,
    text="Esperando archivos",
    text_color=ACCENT_CYAN,
    font=ctk.CTkFont(size=14, weight="bold")
)
status_value.pack(anchor="w", padx=16, pady=(0, 16))

# RESUMEN
card_right_top = ctk.CTkFrame(
    top_container,
    fg_color=BG_CARD,
    corner_radius=18,
    border_width=1,
    border_color=BORDER_COL,
    height=270
)
card_right_top.grid(row=0, column=3, padx=8, pady=8, sticky="nsew")
card_right_top.grid_propagate(False)

summary_section = ctk.CTkFrame(
    card_right_top,
    fg_color=BG_CARD_2,
    corner_radius=12,
    border_width=1,
    border_color=BORDER_COL,
    height=190
)
summary_section.pack(fill="x", padx=12, pady=(12, 8))
summary_section.pack_propagate(False)

ctk.CTkLabel(
    summary_section,
    text="RESUMEN GLOBAL",
    font=ctk.CTkFont(size=15, weight="bold"),
    text_color=ACCENT_CYAN
).pack(anchor="w", padx=12, pady=(10, 5))

resumen_box = ctk.CTkTextbox(
    summary_section,
    height=145,
    fg_color=BG_CARD_2,
    text_color=TEXT_MAIN,
    border_width=0,
    corner_radius=8,
    font=ctk.CTkFont(size=13)
)
resumen_box.pack(fill="x", padx=8, pady=(0, 8))
resumen_box.insert(
    "1.0",
    "Sano: 0\nDegradación inicial: 0\nDegradación severa: 0\nFalla: 0\n\nValidación: no disponible"
)
resumen_box.configure(state="disabled")

total_section = ctk.CTkFrame(
    card_right_top,
    fg_color="#0A2230",
    corner_radius=10,
    border_width=1,
    border_color=BORDER_COL,
    height=62
)
total_section.pack(fill="x", padx=12, pady=(0, 12))
total_section.pack_propagate(False)

ctk.CTkLabel(
    total_section,
    text="TOTAL REGISTROS",
    font=ctk.CTkFont(size=12, weight="bold"),
    text_color=ACCENT_ORNG
).pack(anchor="w", padx=12, pady=(7, 0))

total_value = ctk.CTkLabel(
    total_section,
    text="0",
    font=ctk.CTkFont(size=22, weight="bold"),
    text_color=TEXT_MAIN
)
total_value.pack(anchor="w", padx=12, pady=(0, 5))

# =========================================================
# ZONA CENTRAL
# =========================================================
middle_container = ctk.CTkFrame(app, fg_color=BG_MAIN)
middle_container.pack(fill="both", expand=True, padx=20, pady=(4, 20))

middle_container.grid_columnconfigure(0, weight=4)
middle_container.grid_columnconfigure(1, weight=1)
middle_container.grid_rowconfigure(0, weight=1)

# TABLA
table_card = ctk.CTkFrame(
    middle_container,
    fg_color=BG_CARD,
    corner_radius=18,
    border_width=1,
    border_color=BORDER_COL
)
table_card.grid(row=0, column=0, sticky="nsew", padx=(0, 10), pady=0)

ctk.CTkLabel(
    table_card,
    text="RESULTADOS DE PREDICCIÓN",
    font=ctk.CTkFont(size=18, weight="bold"),
    text_color=TEXT_MAIN
).pack(anchor="w", padx=16, pady=(14, 10))

style = ttk.Style()
style.theme_use("default")

style.configure(
    "Treeview",
    background="#0D2230",
    foreground="#D9F7FF",
    rowheight=30,
    fieldbackground="#0D2230",
    bordercolor="#123B52",
    borderwidth=0,
    font=("Segoe UI", 10)
)

style.configure(
    "Treeview.Heading",
    background="#102C3B",
    foreground="#00E5FF",
    relief="flat",
    font=("Segoe UI", 10, "bold")
)

style.map(
    "Treeview",
    background=[("selected", "#144D66")],
    foreground=[("selected", "#FFFFFF")]
)

table_frame = ctk.CTkFrame(table_card, fg_color="transparent")
table_frame.pack(fill="both", expand=True, padx=12, pady=(0, 12))

initial_columns = (
    "rdson", "cat_rdson", "estado_rdson",
    "vth", "cat_vth", "estado_vth",
    "tj", "cat_tj", "estado_tj",
    "cat_global", "estado_global"
)

tree = ttk.Treeview(table_frame, columns=initial_columns, show="headings")

tree.tag_configure("sano", background="#0F2E2A", foreground="#B8FFF1")
tree.tag_configure("inicial", background="#33260F", foreground="#FFD699")
tree.tag_configure("severa", background="#3A1D1D", foreground="#FFB3B3")
tree.tag_configure("falla", background="#4A1021", foreground="#FFD4E0")
tree.tag_configure("default", background="#0D2230", foreground="#D9F7FF")

tree.pack(fill="both", expand=True)

empty_df = pd.DataFrame(columns=list(initial_columns))
configure_table_columns(empty_df)

# PANEL LATERAL
side_panel = ctk.CTkFrame(
    middle_container,
    fg_color=BG_CARD,
    corner_radius=18,
    border_width=1,
    border_color=BORDER_COL
)
side_panel.grid(row=0, column=1, sticky="nsew", padx=(10, 0), pady=0)

ctk.CTkLabel(
    side_panel,
    text="ESTADOS",
    font=ctk.CTkFont(size=18, weight="bold"),
    text_color=TEXT_MAIN
).pack(anchor="w", padx=16, pady=(16, 14))

summary_column = ctk.CTkFrame(
    side_panel,
    fg_color=BG_CARD_2,
    corner_radius=14,
    border_width=1,
    border_color=BORDER_COL
)
summary_column.pack(fill="x", padx=16, pady=(0, 16))

ctk.CTkLabel(
    summary_column,
    text="SANO",
    font=ctk.CTkFont(size=14, weight="bold"),
    text_color=ACCENT_TEAL
).pack(anchor="w", padx=16, pady=(16, 2))

sano_value = ctk.CTkLabel(
    summary_column,
    text="0",
    font=ctk.CTkFont(size=26, weight="bold"),
    text_color=TEXT_MAIN
)
sano_value.pack(anchor="w", padx=16, pady=(0, 10))

ctk.CTkLabel(
    summary_column,
    text="DEGRADACIÓN INICIAL",
    font=ctk.CTkFont(size=14, weight="bold"),
    text_color=ACCENT_ORNG
).pack(anchor="w", padx=16, pady=(6, 2))

inicial_value = ctk.CTkLabel(
    summary_column,
    text="0",
    font=ctk.CTkFont(size=26, weight="bold"),
    text_color=TEXT_MAIN
)
inicial_value.pack(anchor="w", padx=16, pady=(0, 10))

ctk.CTkLabel(
    summary_column,
    text="DEGRADACIÓN SEVERA",
    font=ctk.CTkFont(size=14, weight="bold"),
    text_color="#FF6B6B"
).pack(anchor="w", padx=16, pady=(6, 2))

severa_value = ctk.CTkLabel(
    summary_column,
    text="0",
    font=ctk.CTkFont(size=26, weight="bold"),
    text_color=TEXT_MAIN
)
severa_value.pack(anchor="w", padx=16, pady=(0, 10))

ctk.CTkLabel(
    summary_column,
    text="FALLA",
    font=ctk.CTkFont(size=14, weight="bold"),
    text_color="#FF2E63"
).pack(anchor="w", padx=16, pady=(6, 2))

falla_value = ctk.CTkLabel(
    summary_column,
    text="0",
    font=ctk.CTkFont(size=26, weight="bold"),
    text_color=TEXT_MAIN
)
falla_value.pack(anchor="w", padx=16, pady=(0, 16))

app.mainloop()