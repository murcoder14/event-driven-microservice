package org.muralis.service.exception;

public class IrrecoverableApiException extends ApiException {
    
    public IrrecoverableApiException(String message) {
        super(message);
    }
    
    public IrrecoverableApiException(String message, Throwable cause) {
        super(message, cause);
    }
}
