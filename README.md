# KOJINGAPLA

**시각장애인을 위한 카메라 기반 보행 보조 어시스턴트**

스마트폰 카메라 영상을 실시간으로 분석하여 두 가지 방식으로 음성 안내를 제공하는 프로토타입입니다.

- **문자 읽기(OCR) 모드** — 표지판, 라벨, 문서, 메뉴 등 화면 속 글자를 읽어 음성으로 안내
- **실시간 보행 안내(Live) 모드** — 전방의 장애물·차량·사람 등을 탐지하고 위치(왼쪽/정면/오른쪽)와 위험도를 분석해 음성으로 안내

iOS(SwiftUI) / Android(Kotlin) 앱이 카메라 프레임을 FastAPI 백엔드로 전송하면, 백엔드는 PaddleOCR(문자 인식)과 YOLOv8n(객체 탐지)을 사용해 음성 안내 문장을 생성하여 반환합니다.

---

## 시스템 구성

```
┌──────────────┐   카메라 프레임   ┌─────────────────────┐
│  모바일 앱     │  (multipart 업로드) │   FastAPI 백엔드       │
│ iOS / Android │ ───────────────► │   POST /analyze      │
│               │                  │                      │
│ - 카메라 캡처   │                  │  mode=text → PaddleOCR │
│ - 모드 전환    │                  │  mode=live → YOLOv8n   │
│ - 음성/햅틱 출력 │ ◄─────────────── │  위치·위험도 분석 후     │
└──────────────┘   음성 안내 JSON   │  음성 안내 문장 생성     │
                                   └─────────────────────┘
```

같은 `/analyze` 엔드포인트가 `mode` 파라미터(`text` / `live`)로 두 모드를 모두 처리합니다.

---

## 프로젝트 구조

```text
KOJINGAPLA/
├── backend/                    # FastAPI 백엔드
│   ├── main.py                 # API 진입점 (/analyze, /health, /health/ocr)
│   ├── ocr_runtime.py          # OCR 실행 환경 설정
│   ├── core/                   # 탐지/OCR 엔진 코어
│   ├── services/               # 비즈니스 로직
│   │   ├── guide_service.py            # live 모드 진입점
│   │   ├── safety_service.py           # 객체 탐지 + 안내 조합
│   │   ├── vision_service.py           # YOLO 추론, 한글 라벨 매핑
│   │   ├── guidance_message_service.py # 위험도 점수·음성 문장 생성
│   │   └── text_service.py             # PaddleOCR 문자 인식
│   └── tests/                  # pytest 테스트
├── frontend/
│   ├── IOS_Swift/Glass/        # SwiftUI iOS 앱
│   └── Android/                # Kotlin(CameraX) Android 앱
├── vision/                     # YOLOv8n 학습/검증/추론 스크립트
│   ├── train.py                # 모델 학습
│   ├── validate.py             # 모델 검증
│   ├── predict.py              # 추론 CLI + 백엔드용 Detector
│   └── tracker_logic.py        # 접근(approach) 추적 로직
├── scripts/
│   └── convert_cvat_to_yolo.py # CVAT 어노테이션 → YOLO 포맷 변환
├── datasets/yolo_sidewalk/     # 인도 보행 데이터셋 (data.yaml, 20개 클래스)
├── runs/                       # 학습/검증/예측 결과물
├── docs/                       # 비전 파이프라인·데모 문서
├── test_images/                # 테스트용 샘플 이미지
├── requirements.txt            # Python 의존성
└── yolov8n.pt                  # YOLOv8n 사전학습 가중치
```

---

## 백엔드 실행

```bash
cd backend
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```

`backend/venv` 대신 새 Python 환경(Ubuntu 22.04 / Python 3.10 권장)을 만든다면 의존성을 먼저 설치하세요.

```bash
# CPU 전용 PyTorch 먼저 설치
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

# 나머지 의존성 설치
python -m pip install -r ../requirements.txt
```

주요 의존성: `ultralytics`(YOLOv8), `paddleocr` / `paddlepaddle`(OCR), `fastapi`, `uvicorn`, `opencv-python-headless`.

### API 엔드포인트

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| `GET` | `/health` | 서버 상태 확인 |
| `GET` | `/health/ocr` | OCR 모델 사용 가능 여부 확인 |
| `POST` | `/analyze` | 이미지 분석. form-data: `image`(파일), `mode`(`live` 또는 `text`) |

`/analyze` 응답 예시(live 모드)에는 `voice_guide`(음성 안내 문장), `warnings`, `risk_level`, `detections`(탐지된 객체 목록) 등이 포함됩니다.

---

## 프론트엔드

### iOS (`frontend/IOS_Swift`)
SwiftUI 기반 `Glass` 앱. 카메라 미리보기, 모드 전환, OCR 프레임 안정성 분석, 중복 음성 억제, 음성 출력(`SpeechManager`), 햅틱 피드백(`HapticFeedbackManager`)을 포함합니다. Xcode에서 `Glass.xcodeproj`를 엽니다.

### Android (`frontend/Android`)
iOS `Glass` 앱의 네이티브 Android 버전. CameraX로 카메라 프레임을 스트리밍하고, ML Kit 한국어 텍스트 인식으로 OCR 대상의 안정성을 로컬에서 판단한 뒤 백엔드 `/analyze`를 호출합니다. Android Studio에서 `frontend/Android`를 엽니다.

> 앱의 `SERVER_URL` / 백엔드 주소를 실행 환경에 맞게 수정해야 합니다. 카메라·진동 기능은 실제 기기에서만 동작합니다.

---

## 비전 파이프라인 (YOLOv8n)

인도 보행 환경에 맞춘 20개 클래스를 탐지합니다: `person, car, truck, bus, bicycle, motorcycle, scooter, wheelchair, stroller, traffic_light, traffic_sign, pole, bollard, bench, tree_trunk, movable_signage, potted_plant, parking_meter, stop, table`.

```bash
# 학습
python -m vision.train --data datasets/yolo_sidewalk/data.yaml

# 검증
python -m vision.validate --weights runs/detect/runs/sidewalk/yolov8n_sidewalk-3/weights/best.pt

# 추론 (이미지 / 웹캠 + 접근 추적)
python -m vision.predict --weights .../best.pt --source test.jpg
python -m vision.predict --weights .../best.pt --source 0 --track-approach
```

CPU 추론은 `yolov8n`, `device="cpu"`, `imgsz=416`, `conf=0.35`, `iou=0.5`, `max_det=20` 설정을 사용합니다. 자세한 내용은 [`docs/vision_pipeline.md`](docs/vision_pipeline.md)를 참고하세요.

### 안내 문장 생성 방식
백엔드는 단순 탐지에 그치지 않고 다음을 수행합니다.

- **위치 분석**: 바운딩 박스 중심을 기준으로 왼쪽/정면/오른쪽 구분
- **위험도 점수화**: 객체 종류, 위치, 화면 점유 면적, 수직 위치, 신뢰도, 접근 여부로 0~100 점수 산출 → `low/medium/high/critical` 등급화
- **거리 추정**: 객체 그룹별 임계값으로 `far/near/close/very_close` 단계 추정
- **접근 추적**: 프레임 간 박스 크기 증가율로 다가오는 물체 감지
- **음성 중복 억제**: 동일 상황의 반복 안내를 쿨다운으로 억제하고, 가중치 기반 템플릿으로 자연스러운 한국어 안내 문장 생성

---

## 데이터셋 준비

CVAT로 어노테이션한 데이터를 YOLO 포맷으로 변환할 수 있습니다.

```bash
python scripts/convert_cvat_to_yolo.py
```

데이터셋 설정은 [`datasets/yolo_sidewalk/data.yaml`](datasets/yolo_sidewalk/data.yaml)에 정의되어 있습니다.

---

## 문서

- [`docs/vision_pipeline.md`](docs/vision_pipeline.md) — YOLOv8n 비전 파이프라인 상세
- [`docs/demo_presentation_summary.md`](docs/demo_presentation_summary.md) — 데모 발표 자료 요약(시스템 아키텍처, 모드별 UX, 학습 결과)

---

## 향후 개선 방향

- YOLO 모델의 재현율(recall) 및 견고성 향상
- 세션별 객체 추적으로 접근 경고 정교화
- 깊이(depth) 기반 거리 추정 강화
- 문자 감지·위험 경고·방향 안내용 햅틱 피드백 확장
- 온디바이스 추론을 통한 지연 시간 단축 및 다국어 OCR 개선
