"""Advisory sentiment API for HALO.

Serves a joblib'd MultinomialNB + TF-IDF pipeline trained on the Twitter
US Airline Sentiment dataset. The response is deliberately tagged as a
demo with a domain caveat — this is a framework demonstration, NOT a
trusted safety signal.
"""

from __future__ import annotations

import os

import joblib
from fastapi import FastAPI
from pydantic import BaseModel

MODEL_PATH = os.path.join(os.path.dirname(__file__), "model.joblib")

app = FastAPI(title="HALO advisory sentiment", version="1.0.0")

MODEL = joblib.load(MODEL_PATH)
LABELS = ["negative", "neutral", "positive"]

CAVEAT = (
    "Model: ComplementNB (airline-sentiment rebalanced). "
    "Trained on Twitter US Airline Sentiment (Kaggle). Toned for airline "
    "customer feedback, not HALO safety reports — treat as an advisory "
    "tone cue, never as severity or truth."
)


class SentimentRequest(BaseModel):
    text: str


class SentimentResponse(BaseModel):
    label: str
    confidence: float
    probabilities: dict[str, float]
    caveat: str
    model: str
    max_score: float


@app.get("/health")
def health() -> dict:
    return {"ok": True, "model": "complement-nb+tfidf(1,2)"}


@app.post("/sentiment", response_model=SentimentResponse)
def sentiment(req: SentimentRequest) -> SentimentResponse:
    text = req.text.strip()
    if not text:
        return SentimentResponse(
            label="neutral",
            confidence=0.0,
            probabilities={"negative": 0.0, "neutral": 0.0, "positive": 0.0},
            caveat=CAVEAT,
            model="complement-nb+tfidf(1,2)",
            max_score=0.0,
        )
    proba = MODEL.predict_proba([text])[0]
    probs = {label: round(float(p), 4) for label, p in zip(LABELS, proba)}
    label = LABELS[int(proba.argmax())]
    confidence = float(proba.max())
    return SentimentResponse(
        label=label,
        confidence=round(confidence, 4),
        probabilities=probs,
        caveat=CAVEAT,
        model="complement-nb+tfidf(1,2)",
        max_score=round(confidence, 4),
    )