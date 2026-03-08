#!/bin/bash

# 설정 변수
IMAGE_NAME="ai-agent"
CONTAINER_NAME="ai-agent"
PORT=8501

echo "1. 기존 컨테이너 중지 및 삭제..."
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

echo "2. Docker 이미지 빌드..."
docker build -t $IMAGE_NAME .

echo "3. 컨테이너 실행..."
docker run -d \
  --name $CONTAINER_NAME \
  -p $PORT:8501 \
  -e AWS_DEFAULT_REGION=ap-northeast-2 \
  --restart unless-stopped \
  $IMAGE_NAME

echo "------------------------------------------"
echo "성공적으로 실행되었습니다!"
echo "접속 주소: http://<EC2_PUBLIC_IP>:$PORT"
echo "로그 확인: docker logs -f $CONTAINER_NAME"
