"""Experiment: does rebalancing stop the model from defaulting to negative?

Compares plain MultinomialNB (current) against:
  A) MultinomialNB with a uniform class prior (0.333 each)
  B) ComplementNB — designed for exactly this shape (imbalanced text where
     the majority class dominates naive Bayes)

Prints per-class recall for each so the choice is made on measured behaviour,
not hope.
"""

from __future__ import annotations

import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import classification_report
from sklearn.model_selection import train_test_split
from sklearn.naive_bayes import ComplementNB, MultinomialNB
from sklearn.pipeline import Pipeline

import train  # reuse load_and_clean / clean_text

DATA_PATH = train.DATA_PATH
LABELS = ["negative", "neutral", "positive"]


def evaluate(name: str, pipe, y_test, y_pred):
    rep = classification_report(
        y_test, y_pred, labels=LABELS, zero_division=0, output_dict=True
    )
    rec = {c: round(rep[c]["recall"], 3) for c in LABELS}
    acc = round(rep["accuracy"], 3)
    wf1 = round(rep["weighted avg"]["f1-score"], 3)
    print(f"{name:28s} acc={acc} weightedF1={wf1} recall=" + str(rec))
    return rec


def main() -> None:
    df = train.load_and_clean(DATA_PATH)
    X_train, X_test, y_train, y_test = train_test_split(
        df["clean"], df["airline_sentiment"],
        test_size=train.TEST_SIZE, random_state=train.RANDOM_STATE, stratify=df["airline_sentiment"],
    )

    base = Pipeline([
        ("tfidf", TfidfVectorizer(ngram_range=(1, 2), sublinear_tf=True)),
        ("nb", MultinomialNB(alpha=1.0)),
    ])
    uniform = Pipeline([
        ("tfidf", TfidfVectorizer(ngram_range=(1, 2), sublinear_tf=True)),
        ("nb", MultinomialNB(alpha=1.0, class_prior=[1 / 3, 1 / 3, 1 / 3])),
    ])
    cnb = Pipeline([
        ("tfidf", TfidfVectorizer(ngram_range=(1, 2), sublinear_tf=True)),
        ("nb", ComplementNB(alpha=1.0)),
    ])

    for name, pipe in [("MultinomialNB (current)", base),
                       ("MultinomialNB uniform prior", uniform),
                       ("ComplementNB", cnb)]:
        pipe.fit(X_train, y_train)
        y_pred = pipe.predict(X_test)
        evaluate(name, pipe, y_test, y_pred)

    # Where does each land on the three probe messages above?
    probes = [
        "someone followed me and stole my phone near the metro",
        "the bus stop got new lights and trains run every ten minutes here",
        "a stranger helped me carry my groceries home, people here seem very kind",
    ]
    for name, pipe in [("base", base), ("uniform", uniform), ("cnb", cnb)]:
        print(name, [pipe.predict([p])[0] for p in probes])


if __name__ == "__main__":
    main()