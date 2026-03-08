# 🤖 Enterprise AI Agent Platform on AWS

> **LangGraph + Amazon Bedrock 기반 Production-Ready RAG 에이전트**  
> 단순한 챗봇을 넘어, 대규모 엔터프라이즈 환경에서 운영 가능한 **신뢰성(Trust) · 확장성(Scalability) · 효율성(Efficiency)**을 갖춘 클라우드 네이티브 AI 서비스

---

## 📖 1. 프로젝트 개요

본 프로젝트는 **완전한 Stateless 구조**, **IaC 기반 자동화 배포**, **기업용 보안 기준을 충족하는 네트워크 설계**를 통해 엔터프라이즈급 AI 에이전트 서비스를 구현합니다.

* ChatBot URL(AWS NLB Domain /w ECS): 
  http://ks2-kai-dev-kabie-ecs-nlb-7c9179426856b610.elb.ap-northeast-2.amazonaws.com/ai-agent/

### 아키텍처 다이어그램

```
외부 사용자 / 내부 사용자
        │
   Route 53 → Security Landing Zone → Transit Gateway / Direct Connect
        │
   NLB → ALB → ECS (Auto Scaling Group, Multi-AZ)
        │               │
   DynamoDB        LangGraph ReAct Agent
   (상태 영속화)         │
                  VPC Endpoint → PrivateLink → Bedrock LLM (Claude Sonnet 4.5)
                        │
              ┌──────────────────────────────────────────┐
              │         Data Integration Pipeline         │
              │  S3 → EventBridge → Bedrock KB (RAG)     │
              │              ↓             ↓              │
              │   Step Functions        Glue ETL          │
              │              └───────────────────────┐   │
              │                         OpenSearch Serverless (VectorDB)
              └──────────────────────────────────────────┘
```

### 핵심 설계 원칙

| 원칙 | 설명 |
|------|------|
| **Stateless 컨테이너** | ECS는 연산만 담당, 모든 대화 상태는 DynamoDB에 영속화 → Auto Scaling / 컨테이너 교체 시에도 100% 대화 연속성 보장 |
| **Multi-AZ 고가용성** | Auto Scaling Group으로 트래픽 스파이크 대응 및 무중단 운영 |
| **보안 네트워크 설계** | Private Subnet + VPC Endpoint(PrivateLink)로 Bedrock API를 인터넷 노출 없이 호출. Transit Gateway + Direct Connect로 온프레미스 하이브리드 연결 |
| **Reproducible IaC** | Terraform으로 전체 인프라를 코드화하여 수분 내 동일 환경 복제·배포 가능 |

---

## 🛠️ 2. 기술 스택

| 레이어 | 기술 | 선택 이유 |
|--------|------|-----------|
| **Frontend / UI** | Streamlit | All-in-one 구조로 백엔드 통합 및 개발 생산성 극대화 |
| **AI Orchestration** | LangGraph (`create_react_agent`), LangChain | ReAct 패턴 기반 자율형 에이전트, 상태 그래프 관리 |
| **LLM** | Amazon Bedrock – Claude Sonnet 4.5 | Global Inference Profile, 최신 고성능 모델 |
| **상태 관리** | Amazon DynamoDB + `langgraph-checkpoint-aws` | 서버리스, 밀리초 단위 응답, LangGraph 체크포인터 네이티브 지원 |
| **Knowledge Base / RAG** | Amazon Bedrock Knowledge Bases | 완전 관리형 RAG 파이프라인 |
| **Vector DB** | Amazon OpenSearch Serverless | 관리형 인덱스 → 서버리스 컬렉션 전환으로 운영 효율 극대화 |
| **컨테이너** | Amazon ECS (Fargate), Amazon ECR | 서버리스 컨테이너, 인프라 관리 부담 제거 |
| **네트워킹** | ALB, NLB, VPC Endpoint, PrivateLink, NAT Gateway, Transit Gateway, Direct Connect | 엔터프라이즈 하이브리드 보안 아키텍처 |
| **CI/CD** | GitLab + GitLab Runner → ECR → ECS | 코드 Push만으로 전체 배포 자동화 |
| **데이터 파이프라인** | AWS Glue (ETL), Step Functions, EventBridge | 이벤트 기반 자동 데이터 수집 및 인덱싱 |
| **모니터링** | CloudWatch, CloudTrail | 인프라 및 API 호출 감사 로그 |
| **LLM 관측성** | LangSmith (LangChain Tracing V2) | 모든 추론·도구 호출 과정 100% 추적 |
| **IaC** | Terraform | 인프라 코드화, 환경 재현성 확보 |

---

## 🧠 RAG Agent 전략

### 에이전트 패턴: ReAct (Reasoning + Acting)

LangGraph의 `create_react_agent`를 통해 LLM이 스스로 도구 사용 여부를 판단하고 실행하는 **자율형 에이전트** 구조입니다.

```
사용자 질문 → LLM 판단 → [도구 필요?]
                              │
                    YES ──────┤──────── NO
                              │              └→ 직접 답변 생성
                   search_knowledge_base() 호출
                              │
                   Bedrock KB retrieve API (Top-3 청크 반환)
                              │
                   관련 컨텍스트 기반 최종 답변 생성
```

### Knowledge Base 구성 전략

| 항목 | 설정값 | 이유 |
|------|--------|------|
| **파서** | Claude Sonnet 4.5 (파운데이션 모델 파서) | PDF 내 복잡한 표·이미지 시각적 구조 정확 이해 |
| **청킹 전략** | 의미체계 청킹 (Semantic Chunking) | 문맥 경계 기준 분리 → 표 데이터 절단 방지, 검색 품질 극대화 |
| **최대 토큰 크기** | 1,024 토큰 | 검색 정밀도와 컨텍스트 길이의 최적 균형 |
| **유사도 임계값** | 95 | 고정밀 청크 경계 설정 (50~99 범위) |
| **검색 결과 수** | 3개 | 정확도 우선, 노이즈 최소화 |
| **Vector DB** | OpenSearch Serverless | Indices → Serverless Collections 전환으로 운영 부담 제거 |

### 상태 영속화 전략

DynamoDB를 LangGraph 체크포인터로 사용. `thread_id` + `checkpoint_ns`를 PK/SK로 세션 데이터를 정밀 관리합니다. 컨테이너 교체·스케일 인아웃 상황에서도 대화 컨텍스트가 완전 보존됩니다.

---

## 🚀 3. 설치 및 실행 방법

### 사전 요구사항

- Python 3.11+
- AWS 계정 및 IAM 권한 (Bedrock, DynamoDB, S3, Bedrock Agent Runtime)
- Amazon Bedrock Claude Sonnet 4.5 모델 활성화 (`ap-northeast-2`)
- DynamoDB 테이블 생성 (`ai-agent-db-ap-northeast-2`)
- Bedrock Knowledge Base 및 S3 버킷 생성 완료

### Step 1. 패키지 설치

```bash
pip install streamlit langchain-aws langgraph langgraph-checkpoint-aws boto3
```

### Step 2. 환경 변수 설정

`app.py` 상단의 글로벌 설정값을 환경에 맞게 수정합니다:

```python
AWS_REGION          = "ap-northeast-2"
DYNAMODB_TABLE_NAME = "ai-agent-db-ap-northeast-2"
KB_ID               = "<your-knowledge-base-id>"
BUCKET_NAME         = "<your-s3-bucket-name>"
MODEL_ID            = "<your-bedrock-inference-profile-arn>"
```

LangSmith 추적 활성화 (선택):

```bash
export LANGCHAIN_API_KEY="<your-langsmith-api-key>"
export LANGCHAIN_PROJECT="ai-agent"
```

### Step 3. 로컬 실행

```bash
streamlit run app.py
```

### Step 4. Docker / ECS 배포 (프로덕션)

```bash
# 로컬 Docker 빌드 & ECR 푸시
docker build -t ai-agent .
docker tag ai-agent:latest <ecr-repo-uri>:latest
docker push <ecr-repo-uri>:latest

# GitLab CI/CD가 ECR → ECS 무중단 배포 자동 수행
# (코드 Push만으로 전체 파이프라인 자동 트리거)
```

### Step 5. Terraform 인프라 프로비저닝 (신규 환경 구성 시)

```bash
cd terraform/
terraform init
terraform apply
# VPC, ECS 클러스터, DynamoDB, OpenSearch, Bedrock KB 등 전체 인프라 자동 생성
```

---

## ✨ 4. 동작 시나리오

### 시나리오 1: 문서 기반 질의응답 (RAG Chat)

1. 사이드바에서 문서 파일(PDF, TXT, CSV 등) 업로드
2. **[업로드 및 동기화 시작]** 클릭 → S3 저장 → Bedrock KB 인제스션 자동 실행 → 완료 알림
3. 채팅창에 문서 관련 질문 입력
4. LangGraph 에이전트가 자율 판단하여 `search_knowledge_base()` 도구 호출
5. OpenSearch Serverless에서 관련 청크 Top-3 검색 후 Claude가 최종 답변 생성
6. 모든 대화 이력은 DynamoDB에 영속화 → 재접속 시에도 맥락 완전 유지

### 시나리오 2: 일반 대화 (멀티턴 메모리)

1. 채팅창에 자유 질문 입력 (문서 검색 불필요)
2. LLM이 도구 호출 없이 직접 답변 생성
3. `thread_id` 기반으로 DynamoDB에 세션 상태 저장 → 컨테이너 재시작 후에도 이전 대화 완전 복원

### 시나리오 3: AI 코드 리뷰 자동화 (GitLab 연동)

1. 개발자가 GitLab에서 MR(Merge Request) 생성 (feature → develop)
2. GitLab Runner가 CI/CD 파이프라인 자동 트리거
3. `/review` API POST 요청 → 변경 파일 목록 전달
4. LLM이 **변경사항 요약 + 보안 취약점 탐지 + 민감정보(Secret) 필터링 + 파일별 품질 분석** 수행
5. GitLab MR 코멘트에 리뷰 결과 자동 게시 → 팀 전체 코드 품질 상향 평준화 및 배포 장애 사전 차단

### 시나리오 4: 데이터 자동 인덱싱 파이프라인

1. S3 버킷에 신규 문서 업로드 이벤트 발생
2. EventBridge 트리거 → Bedrock Knowledge Bases 인제스션 잡 자동 시작
3. Step Functions + Glue ETL이 병렬로 데이터 전처리 및 벡터 인덱싱 수행
4. OpenSearch Serverless 컬렉션 업데이트 완료 → 즉시 검색 가능 상태 전환

---

## ⚠️ 5. 한계점 및 개선 방향

### 현재 한계점

| # | 항목 | 내용 |
|---|------|------|
| 1 | **단일 도구 의존** | `search_knowledge_base` 하나의 도구만 보유. 복합 업무 처리를 위한 다중 도구 통합 필요 |
| 2 | **인증/인가 미구현** | 사용자 로그인 및 역할 기반 접근 제어(RBAC) 부재 |
| 3 | **단일 세션 구조** | `thread_id` 고정값 하드코딩으로 다중 사용자 구분 불가 |
| 4 | **스트리밍 미지원** | `graph_app.invoke()` 동기 호출로 긴 답변 생성 시 UX 불량 (스피너 대기) |
| 5 | **KB 동기화 지연** | 업로드 후 인제스션 완료까지 수분 소요, 즉시 검색 불가 |
| 6 | **비용 가시성 부재** | 토큰 사용량 및 API 호출 비용 모니터링 대시보드 미구축 |
| 7 | **환각(Hallucination) 평가 부재** | AI 답변 품질에 대한 자동화된 검증 로직 없음 |

### 개선 방향

#### 단기 (즉시 적용 가능)
- `thread_id`를 사용자 세션/로그인 ID 기반으로 동적 생성 → 다중 사용자 지원
- `graph_app.stream()`으로 교체하여 스트리밍 답변 출력 구현
- `st.secrets` 또는 AWS Secrets Manager로 민감 정보(API 키, ARN) 외부화

#### 중기 (엔터프라이즈 확장)
- **Amazon Cognito SSO**: 사내 Active Directory / Okta를 Federated IdP로 설정하여 기존 인증 시스템과 매끄럽게 연동
- **MCP(Model Context Protocol) 통합**: n8n + Amazon AgentCore로 사내 레거시 ERP/CRM/DB를 AI 에이전트가 직접 조작 → 단순 Q&A를 넘어 실질적 업무 수행
- **Human-in-the-Loop (HITL)**: LangGraph의 `interrupt` 기능으로 고위험 작업 사전 승인 프로세스 도입

#### 장기 (AI 플랫폼화)
- **Amazon Bedrock Evaluation**: 답변 품질 자동 평가 및 피드백 루프 구축 → 에이전트 자가 개선 선순환 구조
- **멀티 에이전트 아키텍처**: 업무 도메인별 전문 에이전트(법무, 재무, 인사, 무역 등) 분리 및 협업
- **비용 최적화**: 토큰 사용량 기반 알림 + Bedrock 프로비저닝 처리량 예약으로 비용 예측성 확보

---

## 📁 프로젝트 구조

```
.
├── app.py                  # Streamlit 메인 앱 (LangGraph 에이전트 + UI 통합)
├── Dockerfile              # ECS Fargate 배포용 컨테이너 이미지 정의
├── .gitlab-ci.yml          # GitLab CI/CD 파이프라인 (빌드 → ECR 푸시 → ECS 무중단 배포)
├── terraform/              # 전체 AWS 인프라 IaC (VPC, ECS, DynamoDB, Bedrock KB, OpenSearch 등)
└── README.md
```

---

## 📌 결론

> **본 아키텍처는 단순 PoC를 넘어, 실제 엔터프라이즈 환경의 트래픽·보안·운영 요건을 충족하는 Production-Ready 설계입니다.**
>
> Bedrock Knowledge Base의 고정밀 RAG, DynamoDB 기반 완벽한 상태 영속화, Terraform 기반 재현 가능한 인프라를 토대로  
> 비즈니스 도메인 지식을 통합하여 **실질적인 업무 임팩트를 창출하는 신뢰받는 엔터프라이즈 AI 플랫폼**으로 확장할 수 있습니다.
