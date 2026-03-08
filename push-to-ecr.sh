#!/bin/bash

# ==============================================
# GitLab Code Reviewer - ECR 이미지 푸시 스크립트
# ==============================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 변수 설정
AWS_REGION="ap-northeast-2"
ECR_REPOSITORY="kbsec-ai-agent/ai-agent"
LOCAL_IMAGE="ai-agent:latest"

echo -e "${GREEN}🚀 GitLab Code Reviewer → ECR 푸시 시작${NC}"
echo "=================================="
echo "AWS Region: $AWS_REGION"
echo "ECR Repository: $ECR_REPOSITORY"
echo "Local Image: $LOCAL_IMAGE"
echo "=================================="
echo ""

# 1. AWS Account ID 가져오기
echo -e "${YELLOW}📋 Step 1: AWS Account ID 확인${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ AWS Account ID를 가져올 수 없습니다.${NC}"
    echo "AWS CLI가 올바르게 설정되어 있는지 확인하세요."
    exit 1
fi
echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# ECR 전체 URL 구성
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_FULL_PATH="${ECR_URL}/${ECR_REPOSITORY}"

# 2. 로컬에 이미지가 있는지 확인
echo -e "${YELLOW}🔍 Step 2: 로컬 Docker 이미지 확인${NC}"
if docker images | grep -q "ai-agent.*latest"; then
    echo -e "${GREEN}✅ 로컬 이미지 발견:${NC}"
    docker images | grep ai-agent
else
    echo -e "${RED}❌ 로컬에 '$LOCAL_IMAGE' 이미지가 없습니다.${NC}"
    echo ""
    echo "다음 중 하나를 선택하세요:"
    echo "1. 실행 중인 컨테이너에서 이미지 생성:"
    echo "   docker commit ai-agent ai-agent:latest"
    echo ""
    echo "2. Dockerfile로 새로 빌드:"
    echo "   docker build -t ai-agent:latest ."
    exit 1
fi
echo ""

# 3. ECR 저장소 존재 확인 (없으면 생성 제안)
echo -e "${YELLOW}🗂️  Step 3: ECR 저장소 확인${NC}"
if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region $AWS_REGION &>/dev/null; then
    echo -e "${GREEN}✅ ECR 저장소가 존재합니다: $ECR_REPOSITORY${NC}"
else
    echo -e "${YELLOW}⚠️  ECR 저장소가 없습니다. 생성하시겠습니까? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "ECR 저장소 생성 중..."
        aws ecr create-repository \
            --repository-name "$ECR_REPOSITORY" \
            --region $AWS_REGION \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        echo -e "${GREEN}✅ ECR 저장소 생성 완료${NC}"
    else
        echo -e "${RED}❌ ECR 저장소가 필요합니다. 종료합니다.${NC}"
        exit 1
    fi
fi
echo ""

# 4. ECR 로그인
echo -e "${YELLOW}🔐 Step 4: ECR 로그인${NC}"
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_URL

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ ECR 로그인 성공${NC}"
else
    echo -e "${RED}❌ ECR 로그인 실패${NC}"
    exit 1
fi
echo ""

# 5. 이미지 태깅
echo -e "${YELLOW}🏷️  Step 5: Docker 이미지 태깅${NC}"
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)

echo "다음과 같이 태그를 생성합니다:"
echo "  - ${ECR_FULL_PATH}:${IMAGE_TAG}"
echo "  - ${ECR_FULL_PATH}:latest"
echo ""

docker tag $LOCAL_IMAGE ${ECR_FULL_PATH}:${IMAGE_TAG}
docker tag $LOCAL_IMAGE ${ECR_FULL_PATH}:latest

echo -e "${GREEN}✅ 이미지 태깅 완료${NC}"
echo ""

# 6. ECR에 푸시
echo -e "${YELLOW}📤 Step 6: ECR에 이미지 푸시${NC}"
echo "푸시 중: ${ECR_FULL_PATH}:${IMAGE_TAG} ..."
docker push ${ECR_FULL_PATH}:${IMAGE_TAG}

echo ""
echo "푸시 중: ${ECR_FULL_PATH}:latest ..."
docker push ${ECR_FULL_PATH}:latest

echo -e "${GREEN}✅ ECR 푸시 완료!${NC}"
echo ""

# 7. 푸시된 이미지 확인
echo -e "${YELLOW}🔍 Step 7: ECR 이미지 확인${NC}"
aws ecr describe-images \
    --repository-name "$ECR_REPOSITORY" \
    --region $AWS_REGION \
    --query 'sort_by(imageDetails,& imagePushedAt)[-5:].[imageTags[0], imagePushedAt, imageSizeInBytes]' \
    --output table

echo ""
echo -e "${GREEN}✨ 완료!${NC}"
echo "=================================="
echo -e "${BLUE}📋 ECR 이미지 정보:${NC}"
echo "  Repository: $ECR_REPOSITORY"
echo "  Image URI:  ${ECR_FULL_PATH}:latest"
echo "  Tag:        ${IMAGE_TAG}"
echo "=================================="
echo ""
echo -e "${BLUE}🔗 다음 단계:${NC}"
echo "1. ECS Task Definition에서 이미지 URI 사용:"
echo "   ${ECR_FULL_PATH}:latest"
echo ""
echo "2. ECR 콘솔에서 확인:"
echo "   https://console.aws.amazon.com/ecr/repositories/$ECR_REPOSITORY?region=$AWS_REGION"
echo ""
