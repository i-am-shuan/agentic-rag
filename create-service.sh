#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================
# 변수 설정
# ==============================================

AWS_REGION="ap-northeast-2"
ACCOUNT_ID="104871657422"

# 기존 리소스 정보
ECS_CLUSTER="kbsec-ai-cluster"
VPC_ID="vpc-063ea85b9ec96670d"
SUBNET="subnet-0d703fa666bf3d2e7"
SECURITY_GROUP="sg-0bb30025ca057a184"

# IAM Roles
TASK_ROLE_ARN="arn:aws:iam::104871657422:role/kbsec-ai-agent-task-role"
EXECUTION_ROLE_ARN="arn:aws:iam::104871657422:role/ecsTaskExecutionRole"

# 신규 서비스 정보
SERVICE_NAME="ai-agent"
TASK_FAMILY="ai-agent"
CONTAINER_NAME="ai-agent"
CONTAINER_PORT=8501
HOST_PORT=8501

# ECR 이미지
ECR_REPOSITORY="kbsec-ai-agent/ai-agent"
ECR_IMAGE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest"

# Load Balancer
NLB_NAME="ks2-kai-dev-kabie-ecs-nlb"
ALB_NAME="ks2-kai-dev-kabie-ecs-alb"

# 리소스 설정
TASK_CPU="512"
TASK_MEMORY="1024"

echo -e "${GREEN}🚀 ECS 서비스 생성 시작${NC}"
echo "============================================"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Cluster: $ECS_CLUSTER"
echo "Service: $SERVICE_NAME"
echo "Container Port: $CONTAINER_PORT"
echo "CPU: $TASK_CPU, Memory: $TASK_MEMORY"
echo "============================================"
echo ""

# ==============================================
# Step 1: CloudWatch Log Group 생성
# ==============================================

echo -e "${YELLOW}📝 Step 1: CloudWatch Log Group 생성${NC}"

LOG_GROUP_NAME="/ecs/${TASK_FAMILY}"

if aws logs describe-log-groups \
  --log-group-name-prefix $LOG_GROUP_NAME \
  --region $AWS_REGION 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
    echo -e "${BLUE}ℹ️  Log Group이 이미 존재합니다: $LOG_GROUP_NAME${NC}"
else
    aws logs create-log-group \
      --log-group-name $LOG_GROUP_NAME \
      --region $AWS_REGION
    
    aws logs put-retention-policy \
      --log-group-name $LOG_GROUP_NAME \
      --retention-in-days 7 \
      --region $AWS_REGION
    
    echo -e "${GREEN}✅ Log Group 생성 완료: $LOG_GROUP_NAME${NC}"
fi
echo ""

# ==============================================
# Step 2: Security Group에 포트 8501 추가
# ==============================================

echo -e "${YELLOW}🔒 Step 2: Security Group 규칙 확인 및 추가${NC}"

EXISTING_RULE=$(aws ec2 describe-security-groups \
  --group-ids $SECURITY_GROUP \
  --region $AWS_REGION \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`8501\`]" \
  --output text)

if [ -z "$EXISTING_RULE" ]; then
    echo "포트 8501 규칙 추가 중..."
    
    aws ec2 authorize-security-group-ingress \
      --group-id $SECURITY_GROUP \
      --protocol tcp \
      --port 8501 \
      --source-group $SECURITY_GROUP \
      --region $AWS_REGION 2>/dev/null || echo "Self-reference 규칙이 이미 존재할 수 있습니다"
    
    echo -e "${GREEN}✅ Security Group 규칙 추가 완료${NC}"
else
    echo -e "${BLUE}ℹ️  포트 8501 규칙이 이미 존재합니다${NC}"
fi
echo ""

# ==============================================
# Step 3: Target Group 생성
# ==============================================

echo -e "${YELLOW}🎯 Step 3: Target Group 생성${NC}"

TG_NAME="ai-agent-8501-tg"

EXISTING_TG=$(aws elbv2 describe-target-groups \
  --region $AWS_REGION \
  --query "TargetGroups[?TargetGroupName=='${TG_NAME}'].TargetGroupArn" \
  --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_TG" ]; then
    echo -e "${BLUE}ℹ️  Target Group이 이미 존재합니다: $TG_NAME${NC}"
    TG_ARN=$EXISTING_TG
else
    TG_ARN=$(aws elbv2 create-target-group \
      --name $TG_NAME \
      --protocol HTTP \
      --port $CONTAINER_PORT \
      --vpc-id $VPC_ID \
      --target-type ip \
      --health-check-enabled \
      --health-check-path /health \
      --health-check-protocol HTTP \
      --health-check-port traffic-port \
      --health-check-interval-seconds 30 \
      --health-check-timeout-seconds 10 \
      --healthy-threshold-count 2 \
      --unhealthy-threshold-count 3 \
      --region $AWS_REGION \
      --query 'TargetGroups[0].TargetGroupArn' \
      --output text)
    
    echo -e "${GREEN}✅ Target Group 생성 완료${NC}"
fi

echo "  Target Group ARN: $TG_ARN"
echo ""

# ==============================================
# Step 4: ALB에 Listener Rule 추가
# ==============================================

echo -e "${YELLOW}🔀 Step 4: ALB Listener Rule 추가${NC}"

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names $ALB_NAME \
  --region $AWS_REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --region $AWS_REGION \
  --query 'Listeners[?Port==`443`].ListenerArn' \
  --output text)

if [ -z "$LISTENER_ARN" ]; then
    LISTENER_ARN=$(aws elbv2 describe-listeners \
      --load-balancer-arn $ALB_ARN \
      --region $AWS_REGION \
      --query 'Listeners[?Port==`80`].ListenerArn' \
      --output text)
fi

if [ ! -z "$LISTENER_ARN" ]; then
    EXISTING_RULE=$(aws elbv2 describe-rules \
      --listener-arn $LISTENER_ARN \
      --region $AWS_REGION \
      --query "Rules[?Actions[0].TargetGroupArn=='${TG_ARN}'].RuleArn" \
      --output text)
    
    if [ -z "$EXISTING_RULE" ]; then
        MAX_PRIORITY=$(aws elbv2 describe-rules \
          --listener-arn $LISTENER_ARN \
          --region $AWS_REGION \
          --query 'Rules[?Priority!=`default`].Priority' \
          --output text 2>/dev/null | tr '\t' '\n' | sort -n | tail -1)
        
        NEW_PRIORITY=$(( ${MAX_PRIORITY:-100} + 10 ))
        
        aws elbv2 create-rule \
          --listener-arn $LISTENER_ARN \
          --priority $NEW_PRIORITY \
          --conditions Field=path-pattern,Values="/ai-agent*" \
          --actions Type=forward,TargetGroupArn=$TG_ARN \
          --region $AWS_REGION > /dev/null
        
        echo -e "${GREEN}✅ ALB Listener Rule 추가 완료 (Priority: $NEW_PRIORITY)${NC}"
    else
        echo -e "${BLUE}ℹ️  Listener Rule이 이미 존재합니다${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  ALB Listener를 찾을 수 없습니다${NC}"
fi
echo ""

# ==============================================
# Step 5: Task Definition 생성
# ==============================================

echo -e "${YELLOW}📋 Step 5: ECS Task Definition 생성${NC}"

cat > /tmp/ai-agent-taskdef.json <<EOF
{
  "family": "${TASK_FAMILY}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${TASK_CPU}",
  "memory": "${TASK_MEMORY}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "${CONTAINER_NAME}",
      "image": "${ECR_IMAGE}",
      "cpu": 0,
      "memory": ${TASK_MEMORY},
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${CONTAINER_PORT},
          "hostPort": ${HOST_PORT},
          "protocol": "tcp",
          "name": "${CONTAINER_NAME}-${CONTAINER_PORT}-tcp",
          "appProtocol": "http"
        }
      ],
      "environment": [
        { "name": "AWS_REGION", "value": "${AWS_REGION}" },
        { "name": "PORT", "value": "${CONTAINER_PORT}" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${LOG_GROUP_NAME}",
          "awslogs-create-group": "true",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:${CONTAINER_PORT}/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

TASK_DEF_OUTPUT=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/ai-agent-taskdef.json \
  --region $AWS_REGION \
  --output json)

TASK_DEF_REVISION=$(echo $TASK_DEF_OUTPUT | jq -r '.taskDefinition.revision')
TASK_DEF_ARN=$(echo $TASK_DEF_OUTPUT | jq -r '.taskDefinition.taskDefinitionArn')

echo -e "${GREEN}✅ Task Definition 등록 완료 (Revision: ${TASK_DEF_REVISION})${NC}"
echo ""

# ==============================================
# Step 6: ECS Service 생성 또는 업데이트
# ==============================================

echo -e "${YELLOW}🚢 Step 6: ECS Service 생성${NC}"

EXISTING_SERVICE=$(aws ecs describe-services \
  --cluster $ECS_CLUSTER \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[?status==`ACTIVE`].serviceName' \
  --output text 2>/dev/null || echo "")

if [ ! -z "$EXISTING_SERVICE" ]; then
    echo -e "${YELLOW}⚠️  서비스가 이미 존재합니다. 업데이트 진행...${NC}"
    aws ecs update-service \
      --cluster $ECS_CLUSTER \
      --service $SERVICE_NAME \
      --task-definition ${TASK_DEF_ARN} \
      --force-new-deployment \
      --region $AWS_REGION > /dev/null
else
    echo "새 서비스 생성 중..."
    aws ecs create-service \
      --cluster $ECS_CLUSTER \
      --service-name $SERVICE_NAME \
      --task-definition ${TASK_DEF_ARN} \
      --desired-count 1 \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${SUBNET}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=DISABLED}" \
      --load-balancers "[{\"targetGroupArn\":\"${TG_ARN}\",\"containerName\":\"${CONTAINER_NAME}\",\"containerPort\":${CONTAINER_PORT}}]" \
      --region $AWS_REGION > /dev/null
fi
echo -e "${GREEN}✅ ECS Service 배포 명령 완료${NC}"
echo ""

# ==============================================
# Step 7~9: 생략 (모니터링 및 완료 메시지)
# ==============================================

echo -e "${GREEN}✅ 스크립트 실행 완료!${NC}"
rm -f /tmp/ai-agent-taskdef.json
