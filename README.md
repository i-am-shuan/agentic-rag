# 🤖 LangGraph & Knowledge Base Agent

AWS Bedrock, LangGraph, DynamoDB를 활용한 대화 기억 기반 통합 AI 에이전트 웹 애플리케이션입니다.

* Streamlit URL: http://ks2-kai-dev-kabie-ecs-nlb-7c9179426856b610.elb.ap-northeast-2.amazonaws.com/ai-agent/
* Architecture: ![Architecture](https://github.com/i-am-shuan/agentic-rag/blob/main/images/archi.png)
* Streamlit UI: ![Streamlit UI](https://github.com/i-am-shuan/agentic-rag/blob/main/images/streamlit_ui.png)

---

## 📌 주요 기능

- **대화 기억 유지** — DynamoDB 체크포인터를 통해 세션 간 대화 이력을 영속적으로 저장
- **Knowledge Base 검색** — AWS Bedrock Knowledge Base를 활용하여 업로드된 문서에서 관련 정보를 자동 검색
- **문서 업로드 & 동기화** — S3 업로드 후 Knowledge Base 인제스션 잡을 자동 실행
- **LangSmith 트레이싱** — 에이전트 실행 흐름을 LangSmith로 실시간 추적
- **ReAct 에이전트** — LangGraph `create_react_agent`를 사용하여 도구 호출 여부를 스스로 판단

---

## 🏗️ 아키텍처

```
사용자 (Streamlit UI)
        │
        ▼
LangGraph ReAct Agent
        │
   ┌────┴────┐
   │         │
   ▼         ▼
ChatBedrock  search_knowledge_base (Tool)
(Claude)          │
   │         ┌───┴────────────┐
   │         │                │
   │    Bedrock KB       S3 Bucket
   │    (벡터 검색)     (원본 문서)
   │
   ▼
DynamoDB (대화 이력 체크포인터)
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| Frontend | Streamlit |
| AI Agent | LangGraph, LangChain |
| LLM | AWS Bedrock (Claude Sonnet 4.5) |
| 벡터 검색 | AWS Bedrock Knowledge Base |
| 문서 저장소 | AWS S3 |
| 대화 기억 | AWS DynamoDB (LangGraph Checkpointer) |
| 모니터링 | LangSmith |

---

## ⚙️ 환경 설정

### 사전 요구사항

- Python 3.10 이상
- AWS 계정 및 IAM 권한 (Bedrock, S3, DynamoDB, Bedrock Agent Runtime)
- AWS CLI 설정 완료 (`aws configure`)

### 설치

```bash
pip install -r requirements.txt
```

### AWS 리소스 구성

`app.py` 상단의 글로벌 변수를 실제 환경에 맞게 수정합니다.

```python
AWS_REGION = "ap-northeast-2"
DYNAMODB_TABLE_NAME = "ai-agent-db-ap-northeast-2"   # DynamoDB 테이블명
KB_ID = "ROUBEDNHLU"                                  # Bedrock Knowledge Base ID
BUCKET_NAME = "ai-agent-s3-ap-northeast-2"           # S3 버킷명
MODEL_ID = "arn:aws:bedrock:..."                      # Bedrock 추론 프로파일 ARN
```

### DynamoDB 테이블 생성

LangGraph 체크포인터가 사용할 DynamoDB 테이블을 생성합니다.

```bash
aws dynamodb create-table \
  --table-name ai-agent-db-ap-northeast-2 \
  --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

### LangSmith 설정 (선택)

`app.py`의 환경 변수에서 LangSmith API 키를 본인 키로 교체합니다.

```python
os.environ["LANGCHAIN_API_KEY"] = "your-langsmith-api-key"
os.environ["LANGCHAIN_PROJECT"] = "ai-agent"
```

---

## 🚀 실행

```bash
streamlit run app.py
```

브라우저에서 `http://localhost:8501`로 접속합니다.

---

## 📂 사용 방법

### 문서 업로드 및 동기화

1. 좌측 사이드바에서 파일을 선택합니다. (지원 형식: `txt`, `md`, `pdf`, `csv`, `docx`)
2. **업로드 및 동기화 시작** 버튼을 클릭합니다.
3. S3 업로드 → Bedrock Knowledge Base 인제스션이 자동으로 진행됩니다.
4. 동기화 완료 후 채팅에서 문서 내용을 바로 질문할 수 있습니다.

### 채팅

- 일반 질문은 Claude가 직접 답변합니다.
- 업로드된 문서 관련 질문은 에이전트가 `search_knowledge_base` 도구를 자동으로 호출하여 답변합니다.
- 대화 이력은 DynamoDB에 저장되어 새로고침 후에도 유지됩니다.

---

## 📁 프로젝트 구조

```
.
├── app.py              # 메인 애플리케이션
├── requirements.txt    # Python 의존성 목록
└── README.md           # 프로젝트 문서
```

---

## ⚠️ 주의사항

- `app.py`에 하드코딩된 LangSmith API 키와 AWS 리소스 ID는 반드시 교체 후 사용하세요.
- IAM 역할에 Bedrock, S3, DynamoDB에 대한 적절한 권한이 부여되어 있어야 합니다.
- `thread_id`를 변경하면 별도의 대화 세션으로 분리됩니다.
