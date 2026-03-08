import os
import time
import boto3
import streamlit as st
from langchain_aws import ChatBedrock
from langchain_core.messages import HumanMessage
from langgraph.prebuilt import create_react_agent
from langchain_core.tools import tool
from langgraph_checkpoint_aws import DynamoDBSaver

# ==========================================
# 1. 환경 변수 및 글로벌 설정값
# ==========================================
# ✅ 새로 발급받은 LangSmith API 키 및 설정 적용
os.environ["LANGCHAIN_TRACING_V2"] = "true" 
os.environ["LANGCHAIN_ENDPOINT"] = "https://api.smith.langchain.com"
os.environ["LANGCHAIN_API_KEY"] = "LANGCHAIN_API_KEY"
os.environ["LANGCHAIN_PROJECT"] = "ai-agent"

AWS_REGION = "ap-northeast-2"
DYNAMODB_TABLE_NAME = "ai-agent-db-ap-northeast-2"
KB_ID = "ROUBEDNHLU"
BUCKET_NAME = "ai-agent-s3-ap-northeast-2"
MODEL_ID = "arn:aws:bedrock:ap-northeast-2:104871657422:inference-profile/global.anthropic.claude-sonnet-4-5-20250929-v1:0"

st.set_page_config(page_title="통합 AI 에이전트", page_icon="🤖", layout="wide")
st.title("🤖 LangGraph & Knowledge Base Agent")
st.caption("DynamoDB로 기억을 유지하며, 필요시 업로드된 문서를 스스로 검색하여 답변합니다.")

# ==========================================
# 2. 에이전트용 도구(Tool) 정의
# ==========================================
@tool
def search_knowledge_base(query: str) -> str:
    """
    사용자가 업로드한 문서나 특정 지식에 대해 물어볼 때 이 도구를 사용하세요.
    입력된 query를 바탕으로 AWS Bedrock Knowledge Base를 검색하여 관련 문서 내용을 반환합니다.
    """
    client = boto3.client('bedrock-agent-runtime', region_name=AWS_REGION)
    try:
        response = client.retrieve(
            knowledgeBaseId=KB_ID,
            retrievalQuery={'text': query},
            retrievalConfiguration={
                'vectorSearchConfiguration': {'numberOfResults': 3}
            }
        )
        results = response.get('retrievalResults', [])
        if not results:
            return "지식 기반에서 관련 문서를 찾을 수 없습니다."
        
        context = ""
        for r in results:
            uri = r.get('location', {}).get('s3Location', {}).get('uri', '알 수 없는 출처')
            content = r.get('content', {}).get('text', '')
            context += f"[출처: {uri}]\n{content}\n\n"
        return context
    except Exception as e:
        return f"지식 기반 검색 중 오류 발생: {str(e)}"

# ==========================================
# 3. LangGraph 에이전트 초기화 (버그 완벽 제거)
# ==========================================
@st.cache_resource
def init_graph():
    # DynamoDB 체크포인터 연결
    saver = DynamoDBSaver(table_name=DYNAMODB_TABLE_NAME)
    
    # Bedrock LLM 설정
    llm = ChatBedrock(
        model_id=MODEL_ID,
        provider="anthropic",
        region_name=AWS_REGION,
        model_kwargs={"temperature": 0.0}
    )
    
    tools = [search_knowledge_base]
    
    # 🚨 버전 충돌을 일으키던 선택적 파라미터를 제거하여 안정성을 100% 확보했습니다.
    app = create_react_agent(model=llm, tools=tools, checkpointer=saver)
    
    return app

graph_app = init_graph()

# ==========================================
# 4. 사이드바: 파일 업로드 및 지식 기반 동기화
# ==========================================
with st.sidebar:
    st.header("📂 문서 업로드 및 동기화")
    uploaded_file = st.file_uploader("S3에 문서 업로드", type=["txt", "md", "pdf", "csv", "docx"])
    
    if uploaded_file and st.button("업로드 및 동기화 시작"):
        s3_client = boto3.client('s3', region_name=AWS_REGION)
        agent_client = boto3.client('bedrock-agent', region_name=AWS_REGION)
        
        with st.spinner("S3 업로드 및 Knowledge Base 동기화 중..."):
            try:
                s3_client.upload_fileobj(uploaded_file, BUCKET_NAME, uploaded_file.name)
                
                ds_response = agent_client.list_data_sources(knowledgeBaseId=KB_ID)
                ds_id = ds_response['dataSourceSummaries'][0]['dataSourceId']
                
                ingest_response = agent_client.start_ingestion_job(
                    knowledgeBaseId=KB_ID,
                    dataSourceId=ds_id
                )
                job_id = ingest_response['ingestionJob']['ingestionJobId']
                
                while True:
                    status_response = agent_client.get_ingestion_job(
                        knowledgeBaseId=KB_ID,
                        dataSourceId=ds_id,
                        ingestionJobId=job_id
                    )
                    status = status_response['ingestionJob']['status']
                    if status == 'COMPLETE':
                        st.success(f"✅ '{uploaded_file.name}' 동기화 완료!")
                        break
                    elif status in ['FAILED', 'STOPPED']:
                        st.error(f"동기화 실패: {status}")
                        break
                    time.sleep(3)
            except Exception as e:
                st.error(f"오류 발생: {str(e)}")

# ==========================================
# 5. 메인 UI: 채팅 인터페이스
# ==========================================
if "thread_id" not in st.session_state:
    st.session_state.thread_id = "user-session-final-003"

config = {"configurable": {"thread_id": st.session_state.thread_id}}

# 이전 대화 불러오기 (DynamoDB 연동)
state_snapshot = graph_app.get_state(config)
messages = state_snapshot.values.get("messages", []) if state_snapshot.values else []

for msg in messages:
    if msg.type in ["human", "ai"] and msg.content:
        role = "user" if msg.type == "human" else "assistant"
        st.chat_message(role).write(msg.content)

if prompt := st.chat_input("메시지를 입력하거나 문서 내용에 대해 질문해 보세요."):
    st.chat_message("user").write(prompt)

    with st.chat_message("assistant"):
        with st.spinner("답변 생성 중... (LangSmith 기록 중)"):
            input_message = HumanMessage(content=prompt)
            
            # 그래프 실행
            response = graph_app.invoke(
                {"messages": [input_message]},
                config=config
            )
            
            final_msg = response["messages"][-1].content
            st.write(final_msg)
